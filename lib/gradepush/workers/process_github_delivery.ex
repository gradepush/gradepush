defmodule GradePush.Workers.ProcessGitHubDelivery do
  @moduledoc "Processes authenticated GitHub webhooks into local submission records."

  use Oban.Worker, queue: :github, max_attempts: 10

  alias GradePush.Classrooms
  alias GradePush.GitHub
  alias GradePush.GitHub.{Actions, Delivery}
  alias GradePush.Installation
  alias GradePush.Repo
  alias GradePush.Submissions

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => delivery_id}} = job) do
    case Repo.get(Delivery, delivery_id) do
      %Delivery{status: "pending"} = delivery -> process_delivery(delivery, job)
      _ -> :ok
    end
  end

  def perform(_job), do: :ok

  defp process_delivery(delivery, job) do
    case dispatch(delivery) do
      :ok -> mark_delivery(delivery, "processed", nil)
      :ignored -> mark_delivery(delivery, "ignored", nil)
      {:error, reason} -> retry_or_fail(delivery, job, reason)
    end
  end

  defp dispatch(%Delivery{event: "push", payload: payload} = delivery) do
    if app_authored_push?(payload), do: :ignored, else: record_push(delivery, payload)
  end

  defp dispatch(%Delivery{event: "workflow_run", payload: payload}) do
    with %{"repository_id" => github_repository_id, "run_id" => run_id} <- payload,
         {:ok, target} <- Submissions.workflow_target(github_repository_id),
         :ok <- validate_target(target),
         {:ok, credentials} <- Installation.github_app_credentials(),
         {:ok, token_response} <-
           GitHub.installation_token(
             signing_credentials(credentials),
             value(target, :installation_id),
             repository_ids: [github_repository_id]
           ),
         token when is_binary(token) <- value(token_response, :token),
         {:ok, run} <-
           GitHub.get_workflow_run(
             token,
             value(target, :owner_login),
             value(target, :repository_name),
             run_id
           ) do
      process_workflow_run(token, target, run, payload)
    else
      false -> :ignored
      {:error, :not_found} -> :ignored
      {:error, :unknown_repository} -> :ignored
      {:error, :workflow_unavailable} -> :ignored
      :ignored -> :ignored
      :untrusted -> :ignored
      {:error, reason} -> {:error, reason}
      nil -> :ignored
      _ -> :ignored
    end
  end

  defp dispatch(%Delivery{event: "installation", payload: payload}) do
    handle_installation_event(payload)
  end

  defp dispatch(%Delivery{event: "github_app_authorization", payload: payload}) do
    case {payload["action"], payload["github_user_id"]} do
      {"revoked", user_id} when is_integer(user_id) ->
        Installation.revoke_user_authorization(user_id)

      _ ->
        :ignored
    end
  end

  defp dispatch(%Delivery{}), do: :ignored

  defp process_workflow_run(token, target, run, payload) do
    case classify_workflow_run(run, target, payload) do
      {:ok, grading_run} -> verify_and_grade_workflow(token, target, grading_run)
      {:error, :workflow_modified} -> record_untrusted_result(target, run)
      :ignored -> :ignored
    end
  end

  defp verify_and_grade_workflow(token, target, run) do
    case verify_workflow_file(token, target, run) do
      :ok -> record_grade(token, target, run)
      :untrusted -> record_untrusted_result(target, run)
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_push(delivery, payload) do
    case Submissions.record_push_for_github_repository(
           payload["repository_id"],
           payload["commit_sha"],
           payload["branch"],
           delivery.received_at,
           delivery.delivery_id
         ) do
      {:ok, _push} -> :ok
      {:error, :not_found} -> :ignored
      {:error, reason} -> {:error, reason}
    end
  end

  defp app_authored_push?(%{"sender_type" => "Bot", "sender_login" => sender_login})
       when is_binary(sender_login) do
    case Installation.github_app_metadata() do
      %{slug: slug} when is_binary(slug) and slug != "" -> sender_login == slug <> "[bot]"
      _ -> false
    end
  end

  defp app_authored_push?(_payload), do: false

  defp handle_installation_event(payload) do
    case {payload["installation_id"], payload["action"]} do
      {installation_id, action}
      when is_integer(installation_id) and action in ["deleted", "suspend", "unsuspend"] ->
        case Classrooms.handle_github_installation_event(installation_id, action, [], []) do
          {:ok, _count} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        :ignored
    end
  end

  defp validate_target(target) do
    required =
      ~w(installation_id owner_login repository_name repository_id assignment_id workflow_id workflow_path workflow_file_sha tests)
      |> Enum.all?(fn key -> not is_nil(value(target, key)) end)

    if required and is_list(value(target, :tests)) and value(target, :tests) != [],
      do: :ok,
      else: :ignored
  end

  defp classify_workflow_run(run, target, payload) do
    path = value(run, :path)
    workflow_path = if is_binary(path), do: path |> String.split("@", parts: 2) |> hd()

    cond do
      not run_id_matches?(run, payload) -> :ignored
      not workflow_id_matches?(run, target, payload) -> :ignored
      not grading_run?(run, payload) -> :ignored
      workflow_path != value(target, :workflow_path) -> {:error, :workflow_modified}
      true -> {:ok, run}
    end
  end

  defp run_id_matches?(run, payload), do: value(run, :id) == payload["run_id"]

  defp workflow_id_matches?(run, target, payload) do
    workflow_id = value(target, :workflow_id)
    value(run, :workflow_id) == workflow_id and payload["workflow_id"] == workflow_id
  end

  defp grading_run?(run, payload) do
    value(run, :event) == "push" and value(run, :status) == "completed" and
      is_binary(value(run, :head_sha)) and same_sha?(value(run, :head_sha), payload["commit_sha"])
  end

  defp verify_workflow_file(token, target, run) do
    case GitHub.get_repository_file(
           token,
           value(target, :owner_login),
           value(target, :repository_name),
           value(target, :workflow_path),
           value(run, :head_sha)
         ) do
      {:ok, file} ->
        if same_sha?(value(file, :sha), value(target, :workflow_file_sha)),
          do: :ok,
          else: :untrusted

      {:error, {:http_error, 404}} ->
        :untrusted

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :invalid_github_response}
    end
  end

  defp record_grade(token, target, run) do
    with {:ok, jobs} <-
           GitHub.list_workflow_jobs(
             token,
             value(target, :owner_login),
             value(target, :repository_name),
             value(run, :id)
           ),
         {:ok, grading} <- Actions.job_results(jobs, value(target, :tests)),
         {:ok, _grade} <-
           Submissions.record_grade(
             value(target, :assignment_id),
             value(target, :repository_id),
             grade_attributes(run, grading)
           ) do
      :ok
    else
      {:error, :not_found} -> :ignored
      {:error, :push_not_recorded} -> :ignored
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_grading_result}
    end
  end

  defp record_untrusted_result(target, run) do
    case Submissions.record_untrusted_result(
           value(target, :assignment_id),
           value(target, :repository_id),
           %{
             commit_sha: value(run, :head_sha),
             run_id: value(run, :id),
             html_url: github_url(value(run, :html_url)),
             reason: "workflow_modified"
           }
         ) do
      {:ok, _grade} -> :ok
      {:error, :not_found} -> :ignored
      {:error, reason} -> {:error, reason}
    end
  end

  defp grade_attributes(run, grading) do
    %{
      commit_sha: value(run, :head_sha),
      run_id: value(run, :id),
      status: run_status(value(run, :conclusion)),
      score: grading.score,
      max_score: grading.max_score,
      html_url: github_url(value(run, :html_url)),
      tests: grading.tests
    }
  end

  defp run_status("success"), do: "success"
  defp run_status("cancelled"), do: "cancelled"
  defp run_status("timed_out"), do: "timed_out"
  defp run_status(_), do: "failure"

  defp github_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "github.com", userinfo: nil, fragment: nil} -> url
      _ -> nil
    end
  end

  defp github_url(_), do: nil

  defp same_sha?(left, right) when is_binary(left) and is_binary(right),
    do: String.downcase(left) == String.downcase(right)

  defp same_sha?(_, _), do: false

  defp retry_or_fail(delivery, job, reason) do
    if job.attempt >= job.max_attempts do
      mark_delivery(delivery, "failed", error_code(reason))
      {:discard, error_code(reason)}
    else
      {:error, error_code(reason)}
    end
  end

  defp mark_delivery(delivery, status, error_code) do
    delivery
    |> Ecto.Changeset.change(%{
      status: status,
      processed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      last_error: error_code
    })
    |> Repo.update!()

    :ok
  end

  defp error_code(reason)
       when reason in [
              :not_configured,
              :unauthorized,
              :forbidden,
              :rate_limited,
              :submission_update_failed,
              :transport,
              :github_unavailable
            ],
       do: Atom.to_string(reason)

  defp error_code({:rate_limited, _seconds}), do: "rate_limited"
  defp error_code({:github_unavailable, _status}), do: "github_unavailable"
  defp error_code(_), do: "processing_failed"

  defp signing_credentials(credentials),
    do: Map.take(credentials, [:app_id, :client_id, :private_key])

  defp value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp value(_, _), do: nil
end
