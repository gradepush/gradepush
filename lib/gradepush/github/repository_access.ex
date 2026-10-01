defmodule GradePush.GitHub.RepositoryAccess do
  @moduledoc "Reconciles direct repository access using current membership and stable GitHub IDs."

  alias GradePush.Assignments
  alias GradePush.GitHub
  alias GradePush.Installation
  alias GradePush.Repo

  def sync_subject(subject_id) when is_integer(subject_id) do
    # Both provisioning and membership jobs serialize their permission changes here.
    # A transaction-scoped lock also releases when a worker crashes or is cancelled.
    result =
      Repo.transaction(
        fn ->
          %{rows: [[locked?]]} =
            Repo.query!("SELECT pg_try_advisory_xact_lock(hashtextextended($1, 0))", [
              "gradepush:repository-access:#{subject_id}"
            ])

          if locked?, do: sync_current_subject(subject_id), else: {:error, :access_sync_busy}
        end,
        timeout: 120_000
      )

    Assignments.publish_repository_access(subject_id)

    case result do
      {:ok, outcome} -> outcome
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_current_subject(subject_id) do
    with {:ok, intent} <-
           Assignments.provisioning_intent(subject_id, allow_empty_recipients: true),
         repository_id when is_integer(repository_id) <- intent.repository.github_repository_id do
      result =
        sync_collaborators(
          intent.installation_id,
          repository_id,
          intent.repository.owner_login,
          intent.repository.name,
          intent.recipients,
          intent.removed_recipients
        )

      Assignments.repository_access_synced(subject_id, intent.access_version, result)
      result
    else
      nil -> {:error, :repository_not_ready}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_collaborators(
         installation_id,
         repository_id,
         owner,
         repository,
         recipients,
         removed
       ) do
    case validate_repository_scope(installation_id, repository_id, owner, repository, recipients) do
      :ok ->
        sync_valid_repository(
          installation_id,
          repository_id,
          owner,
          repository,
          recipients,
          removed
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_repository_scope(installation_id, repository_id, owner, repository, recipients)
       when is_integer(installation_id) and installation_id > 0 and is_integer(repository_id) and
              repository_id > 0 and is_binary(owner) and is_binary(repository) and
              is_list(recipients),
       do: :ok

  defp validate_repository_scope(
         _installation_id,
         _repository_id,
         _owner,
         _repository,
         _recipients
       ),
       do: {:error, :invalid_repository}

  defp sync_valid_repository(_installation_id, _repository_id, _owner, _repository, [], []),
    do: :ok

  defp sync_valid_repository(
         installation_id,
         repository_id,
         owner,
         repository,
         recipients,
         removed
       ) do
    with {:ok, token} <- repository_token(installation_id, repository_id),
         :ok <- remove_recipients(token, owner, repository, removed),
         :ok <- add_recipients(token, owner, repository, recipients),
         {:ok, remote} <- GitHub.get_repository(token, owner, repository),
         true <- value(remote, :id) == repository_id do
      :ok
    else
      false -> {:error, :invalid_repository}
      error -> error
    end
  end

  defp remove_recipients(_token, _owner, _repository, []), do: :ok

  defp remove_recipients(token, owner, repository, removed) do
    with {:ok, invitations} <- GitHub.list_repository_invitations(token, owner, repository) do
      revoke_recipients(token, owner, repository, removed, invitations)
    end
  end

  defp revoke_recipients(token, owner, repository, removed, invitations) do
    Enum.reduce_while(removed, :ok, fn recipient, :ok ->
      result =
        with :ok <- cancel_invitations(token, owner, repository, invitations, recipient),
             do: remove_recipient(token, owner, repository, recipient)

      if result == :ok, do: {:cont, :ok}, else: {:halt, result}
    end)
  end

  defp cancel_invitations(token, owner, repository, invitations, recipient) do
    invitations
    |> Enum.filter(&(get_in(&1, ["invitee", "id"]) == value(recipient, :github_id)))
    |> Enum.reduce_while(:ok, fn invitation, :ok ->
      result =
        case invitation["id"] do
          id when is_integer(id) and id > 0 ->
            GitHub.delete_repository_invitation(token, owner, repository, id) |> deleted()

          _ ->
            {:error, :invalid_github_response}
        end

      if result == :ok, do: {:cont, :ok}, else: {:halt, result}
    end)
  end

  defp remove_recipient(token, owner, repository, recipient) do
    # Cancel invitations first, then remove access in case an invitation was just accepted.
    # Resolve the current login: an old username may now belong to another GitHub account.
    with {:ok, login} <- recipient_login(token, recipient) do
      GitHub.remove_collaborator(token, owner, repository, login) |> deleted()
    end
  end

  defp deleted({:ok, _}), do: :ok
  defp deleted({:error, {:http_error, 404}}), do: :ok
  defp deleted(error), do: error

  defp repository_token(installation_id, repository_id) do
    with {:ok, credentials} <- Installation.github_app_credentials(),
         {:ok, token_response} <-
           GitHub.installation_token(
             signing_credentials(credentials),
             installation_id,
             repository_ids: [repository_id]
           ),
         token when is_binary(token) and token != "" <- value(token_response, :token) do
      {:ok, token}
    else
      nil -> {:error, :invalid_github_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp add_recipients(token, owner, repository, recipients) do
    Enum.reduce_while(recipients, :ok, fn recipient, :ok ->
      case add_recipient(token, owner, repository, recipient) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp add_recipient(token, owner, repository, recipient) do
    with {:ok, login} <- recipient_login(token, recipient),
         {:ok, _invitation} <- GitHub.add_collaborator(token, owner, repository, login, "push") do
      :ok
    end
  end

  defp recipient_login(access_token, recipient) do
    with github_id when is_integer(github_id) and github_id > 0 <- value(recipient, :github_id),
         {:ok, user} <- GitHub.get_user_by_id(access_token, github_id),
         true <- value(user, :id) == github_id,
         login when is_binary(login) <- value(user, :login),
         true <- valid_login?(login) do
      {:ok, login}
    else
      {:error, {:http_error, 404}} -> {:error, :invalid_github_recipient}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_github_recipient}
    end
  end

  defp valid_login?(login) when is_binary(login) and byte_size(login) in 1..39,
    do: Regex.match?(~r/\A[a-zA-Z0-9-]+\z/, login)

  defp valid_login?(_login), do: false

  defp signing_credentials(credentials),
    do: Map.take(credentials, [:app_id, :client_id, :private_key])

  defp value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp value(_map, _key), do: nil
end
