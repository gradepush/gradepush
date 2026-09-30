defmodule GradePush.GitHub.Webhooks do
  @moduledoc false

  import Ecto.Query

  alias GradePush.GitHub.Delivery
  alias GradePush.Installation
  alias GradePush.Repo
  alias GradePush.Workers.ProcessGitHubDelivery

  @max_body_size 2_000_000
  @events ~w(push workflow_run installation installation_repositories github_app_authorization ping)

  def receive(raw_body, headers) when is_binary(raw_body) and is_list(headers) do
    with :ok <- validate_body(raw_body),
         {:ok, delivery_id} <- required_header(headers, "x-github-delivery"),
         {:ok, event} <- required_header(headers, "x-github-event"),
         {:ok, signature} <- required_header(headers, "x-hub-signature-256"),
         {:ok, app_credentials} <- Installation.github_app_credentials(),
         :ok <- verify_signature(raw_body, signature, app_credentials.webhook_secret),
         {:ok, decoded} when is_map(decoded) <- Jason.decode(raw_body),
         {status, payload, action} <- normalize(event, decoded),
         :ok <- validate_delivery_id(delivery_id),
         :ok <- validate_event(event),
         {:ok, result} <- persist_delivery(delivery_id, event, action, status, payload, raw_body) do
      {:ok, result}
    else
      {:error, :not_configured} -> {:error, :not_configured}
      {:error, reason} -> {:error, reason}
      {:ok, _decoded} -> {:error, :invalid_webhook}
      _ -> {:error, :invalid_webhook}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_configured}
  end

  def receive(_raw_body, _headers), do: {:error, :invalid_webhook}

  @doc "Requeues exhausted grading deliveries once their server-observed push exists."
  def reconcile_grading do
    Repo.transaction(fn ->
      deliveries =
        from(delivery in Delivery,
          join: repository in GradePush.Assignments.Repository,
          on:
            fragment("?->>'repository_id'", delivery.payload) ==
              fragment("?::text", repository.github_repository_id),
          join: push in GradePush.Submissions.Push,
          on:
            push.repository_id == repository.id and
              push.commit_sha == fragment("?->>'commit_sha'", delivery.payload),
          where:
            delivery.event == "workflow_run" and delivery.status == "failed" and
              delivery.last_error == "push_not_recorded",
          order_by: delivery.id,
          limit: 100,
          lock: fragment("FOR UPDATE OF ? SKIP LOCKED", delivery),
          select: delivery
        )
        |> Repo.all()
        |> Enum.uniq_by(& &1.id)

      Enum.each(deliveries, &recover_failed_delivery/1)
      length(deliveries)
    end)
  end

  def verify_signature(raw_body, signature, secret)
      when is_binary(raw_body) and is_binary(signature) and is_binary(secret) and
             byte_size(secret) > 0 do
    with "sha256=" <> signature_hex <- signature,
         true <- Regex.match?(~r/\A[0-9a-fA-F]{64}\z/, signature_hex) do
      expected =
        :crypto.mac(:hmac, :sha256, secret, raw_body)
        |> Base.encode16(case: :lower)

      if Plug.Crypto.secure_compare(expected, String.downcase(signature_hex)),
        do: :ok,
        else: {:error, :invalid_signature}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  def verify_signature(_raw_body, _signature, _secret), do: {:error, :invalid_signature}

  defp persist_delivery(delivery_id, event, action, status, payload, raw_body) do
    digest = :crypto.hash(:sha256, raw_body)

    attrs = %{
      delivery_id: delivery_id,
      event: event,
      action: action,
      payload_sha256: digest,
      payload: payload,
      status: status,
      received_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }

    case Repo.transaction(fn ->
           persist_delivery_transaction(attrs, delivery_id, digest, status)
         end) do
      {:ok, outcome} -> {:ok, outcome}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_delivery_transaction(attrs, delivery_id, digest, status) do
    case Repo.insert_all(Delivery, [attrs],
           on_conflict: :nothing,
           conflict_target: [:delivery_id],
           returning: [:id]
         ) do
      {1, [%{id: id}]} ->
        enqueue_delivery(id, status)
        delivery_outcome(status)

      {0, []} ->
        duplicate_delivery(delivery_id, digest)
    end
  end

  defp enqueue_delivery(id, "pending") do
    %{delivery_id: id}
    |> ProcessGitHubDelivery.new()
    |> Oban.insert!()
  end

  defp enqueue_delivery(_id, _status), do: :ok

  defp delivery_outcome("ignored"), do: :ignored
  defp delivery_outcome(_status), do: :accepted

  defp duplicate_delivery(delivery_id, digest) do
    case Repo.one(
           from(delivery in Delivery,
             where: delivery.delivery_id == ^delivery_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Delivery{payload_sha256: existing_digest} = delivery ->
        if Plug.Crypto.secure_compare(existing_digest, digest),
          do: recover_failed_delivery(delivery),
          else: Repo.rollback(:delivery_payload_conflict)

      nil ->
        Repo.rollback(:delivery_persistence_failed)
    end
  end

  defp recover_failed_delivery(%Delivery{status: "failed"} = delivery) do
    delivery
    |> Delivery.changeset(%{status: "pending", processed_at: nil, last_error: nil})
    |> Repo.update!()

    enqueue_delivery(delivery.id, "pending")
    :accepted
  end

  defp recover_failed_delivery(_delivery), do: :duplicate

  defp normalize("push", payload) do
    repository = object(payload["repository"])
    owner = object(repository["owner"])
    sender = object(payload["sender"])
    after_sha = payload["after"]
    reference = payload["ref"]

    if is_binary(after_sha) and valid_sha?(after_sha) and not payload["deleted"] and
         positive_integer?(repository["id"]) and is_binary(owner["login"]) and
         is_binary(repository["name"]) and
         is_binary(reference) and String.starts_with?(reference, "refs/heads/") do
      {"pending",
       Map.merge(
         %{
           "repository_id" => positive_integer(repository["id"]),
           "owner_login" => bounded(owner["login"], 100),
           "repository_name" => bounded(repository["name"], 100),
           "commit_sha" => String.downcase(after_sha),
           "branch" => bounded(String.replace_prefix(reference, "refs/heads/", ""), 255)
         },
         sender_attributes(sender)
       ), payload["action"]}
    else
      {"ignored", %{}, payload["action"]}
    end
  end

  defp normalize("workflow_run", payload) do
    repository = object(payload["repository"])
    run = object(payload["workflow_run"])

    if payload["action"] == "completed" and run["status"] == "completed" and
         positive_integer?(repository["id"]) and positive_integer?(run["id"]) and
         positive_integer?(Map.get(run, "run_attempt", 1)) and
         valid_sha?(run["head_sha"]) do
      {"pending",
       %{
         "repository_id" => repository["id"],
         "owner_login" => bounded(get_in(repository, ["owner", "login"]), 100),
         "repository_name" => bounded(repository["name"], 100),
         "run_id" => run["id"],
         "run_attempt" => Map.get(run, "run_attempt", 1),
         "workflow_id" => positive_integer(run["workflow_id"]),
         "workflow_path" => bounded(run["path"], 255),
         "commit_sha" => String.downcase(run["head_sha"]),
         "branch" => bounded(run["head_branch"], 255),
         "event" => bounded(run["event"], 100),
         "status" => bounded(run["status"], 50),
         "conclusion" => bounded(run["conclusion"], 50),
         "html_url" => bounded(run["html_url"], 500)
       }, payload["action"]}
    else
      {"ignored", %{}, payload["action"]}
    end
  end

  defp normalize("installation", payload) do
    installation = object(payload["installation"])
    account = object(installation["account"])

    {"pending",
     %{
       "installation_id" => positive_integer(installation["id"]),
       "account_id" => positive_integer(account["id"]),
       "account_login" => bounded(account["login"], 100),
       "action" => bounded(payload["action"], 50)
     }, payload["action"]}
  end

  defp normalize("installation_repositories", payload) do
    installation = object(payload["installation"])

    {"pending",
     %{
       "installation_id" => positive_integer(installation["id"]),
       "added_repository_ids" => repository_ids(payload["repositories_added"]),
       "removed_repository_ids" => repository_ids(payload["repositories_removed"]),
       "action" => bounded(payload["action"], 50)
     }, payload["action"]}
  end

  defp normalize("github_app_authorization", payload) do
    sender = object(payload["sender"])

    {"pending",
     %{
       "github_user_id" => positive_integer(sender["id"]),
       "action" => bounded(payload["action"], 50)
     }, payload["action"]}
  end

  defp normalize("ping", _payload), do: {"ignored", %{}, nil}
  defp normalize(_event, _payload), do: {"ignored", %{}, nil}

  defp validate_body(body) when byte_size(body) in 1..@max_body_size, do: :ok
  defp validate_body(_), do: {:error, :invalid_webhook}

  defp validate_event(event) when event in @events, do: :ok
  defp validate_event(_), do: {:error, :unsupported_event}

  defp validate_delivery_id(value) when byte_size(value) in 1..100, do: :ok
  defp validate_delivery_id(_), do: {:error, :invalid_webhook}

  defp required_header(headers, name) do
    values =
      for {key, value} <- headers,
          is_binary(key) and String.downcase(key) == name,
          do: value

    case values do
      [value] when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :invalid_webhook}
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value
  defp positive_integer(_), do: nil
  defp positive_integer?(value), do: not is_nil(positive_integer(value))

  defp sender_attributes(%{"type" => type, "login" => login})
       when is_binary(type) and is_binary(login),
       do: %{"sender_type" => bounded(type, 20), "sender_login" => bounded(login, 100)}

  defp sender_attributes(_sender), do: %{}

  defp repository_ids(repositories) when is_list(repositories) do
    repositories
    |> Enum.map(&(object(&1)["id"] |> positive_integer()))
    |> Enum.reject(&is_nil/1)
    |> Enum.take(100)
  end

  defp repository_ids(_), do: []

  defp object(value) when is_map(value), do: value
  defp object(_), do: %{}

  defp valid_sha?(sha) when is_binary(sha), do: Regex.match?(~r/\A[0-9a-fA-F]{40,64}\z/, sha)
  defp valid_sha?(_), do: false

  defp bounded(value, max) when is_binary(value), do: String.slice(value, 0, max)
  defp bounded(_, _), do: nil
end
