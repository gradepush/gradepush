defmodule GradePush.GitHub.RepositoryAccess do
  @moduledoc "Grants repository access to recipients resolved from stable GitHub account IDs."

  alias GradePush.GitHub
  alias GradePush.Installation

  def sync_collaborators(installation_id, repository_id, owner, repository, recipients) do
    case validate_repository_scope(installation_id, repository_id, owner, repository, recipients) do
      :ok -> sync_valid_repository(installation_id, repository_id, owner, repository, recipients)
      {:error, _reason} = error -> error
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

  defp sync_valid_repository(_installation_id, _repository_id, _owner, _repository, []), do: :ok

  defp sync_valid_repository(installation_id, repository_id, owner, repository, recipients) do
    with {:ok, token} <- repository_token(installation_id, repository_id) do
      add_recipients(token, owner, repository, recipients)
    end
  end

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
