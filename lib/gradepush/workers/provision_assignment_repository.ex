defmodule GradePush.Workers.ProvisionAssignmentRepository do
  @moduledoc "Creates and configures an assignment repository idempotently."

  use Oban.Worker, queue: :github, max_attempts: 10

  alias GradePush.Assignments
  alias GradePush.GitHub
  alias GradePush.GitHub.RepositoryAccess
  alias GradePush.Installation

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subject_id" => subject_id}} = job) do
    with {:ok, intent} <- Assignments.provisioning_intent(subject_id),
         {:ok, repository} <- ensure_repository(intent),
         {:ok, _repository_record} <-
           Assignments.repository_created(subject_id, repository_record(repository)),
         {:ok, workflow} <- ensure_workflow(intent, repository),
         :ok <- grant_student_access(intent, repository),
         {:ok, _repository_record} <-
           Assignments.repository_provisioned(
             subject_id,
             Map.merge(repository_record(repository), workflow)
           ) do
      :ok
    else
      {:error, reason} = error ->
        if permanent_failure?(reason) or job.attempt >= job.max_attempts do
          Assignments.repository_provisioning_failed(subject_id, failure_code(reason))
          {:discard, failure_code(reason)}
        else
          error
        end
    end
  end

  defp ensure_repository(intent) do
    case existing_repository(intent) do
      %{github_repository_id: repository_id} = repository when not is_nil(repository_id) ->
        with {:ok, credentials} <- Installation.github_app_credentials(),
             {:ok, token_response} <-
               GitHub.installation_token(
                 signing_credentials(credentials),
                 field(intent, :installation_id)
               ),
             {:ok, remote} <-
               GitHub.get_repository(
                 token(token_response),
                 field(intent, :organization_login),
                 field(repository, :name)
               ),
             true <- remote["id"] == repository_id do
          {:ok, remote}
        else
          false -> {:error, :repository_identity_mismatch}
          error -> error
        end

      _ ->
        create_repository(intent)
    end
  end

  defp create_repository(intent) do
    with {:ok, credentials} <- Installation.github_app_credentials(),
         {:ok, token_response} <-
           GitHub.installation_token(
             signing_credentials(credentials),
             field(intent, :installation_id)
           ),
         {:ok, repository} <-
           GitHub.create_repository(token(token_response), field(intent, :organization_login), %{
             repository_name: field(intent, :repository_name),
             visibility: field(intent, :visibility),
             description: field(intent, :description),
             template_owner: field(intent, :template_owner),
             template_name: field(intent, :template_name)
           }),
         :ok <- validate_created_repository(repository, intent) do
      {:ok, repository}
    end
  end

  defp ensure_workflow(intent, repository) do
    if field(intent, :autograding_enabled) do
      with tests when is_list(tests) and tests != [] <- field(intent, :workflow_config),
           {:ok, credentials} <- Installation.github_app_credentials(),
           {:ok, token_response} <-
             GitHub.installation_token(
               signing_credentials(credentials),
               field(intent, :installation_id),
               repository_ids: [repository["id"]]
             ),
           {:ok, workflow} <-
             GitHub.install_autograding_workflow(
               token(token_response),
               repository["owner"]["login"],
               repository["name"],
               tests
             ) do
        {:ok, workflow}
      else
        nil -> {:error, :missing_autograding_tests}
        [] -> {:error, :missing_autograding_tests}
        {:error, reason} -> {:error, reason}
        _ -> {:error, :invalid_autograding_config}
      end
    else
      {:ok, %{}}
    end
  end

  defp grant_student_access(intent, repository) do
    RepositoryAccess.sync_collaborators(
      field(intent, :installation_id),
      repository["id"],
      get_in(repository, ["owner", "login"]),
      repository["name"],
      field(intent, :recipients) || []
    )
  end

  defp validate_created_repository(repository, intent) do
    owner = get_in(repository, ["owner", "login"])

    cond do
      not is_integer(repository["id"]) or repository["id"] <= 0 ->
        {:error, :invalid_github_repository_response}

      not is_binary(repository["name"]) or repository["name"] != field(intent, :repository_name) ->
        {:error, :repository_identity_mismatch}

      not is_binary(owner) or
          String.downcase(owner) != String.downcase(field(intent, :organization_login)) ->
        {:error, :repository_identity_mismatch}

      not is_binary(repository["html_url"]) ->
        {:error, :invalid_github_repository_response}

      true ->
        :ok
    end
  end

  defp repository_record(repository) do
    %{
      github_repository_id: repository["id"],
      owner_login: get_in(repository, ["owner", "login"]),
      name: repository["name"],
      full_name: repository["full_name"],
      html_url: repository["html_url"]
    }
  end

  defp existing_repository(intent) do
    field(intent, :repository) ||
      %{
        github_repository_id: field(intent, :github_repository_id),
        owner_login: field(intent, :owner_login),
        name: field(intent, :name),
        full_name: field(intent, :full_name),
        html_url: field(intent, :html_url)
      }
  end

  defp signing_credentials(credentials) do
    Map.take(credentials, [:app_id, :client_id, :private_key])
  end

  defp token(%{"token" => value}) when is_binary(value), do: value
  defp token(_), do: nil

  defp field(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp permanent_failure?(reason) do
    reason in [
      :repository_name_taken,
      :repository_identity_mismatch,
      :repository_identity_conflict,
      :invalid_github_repository_response,
      :missing_autograding_tests,
      :invalid_autograding_tests,
      :invalid_autograding_config,
      :workflow_already_exists,
      :repository_creation_rejected,
      :invalid_permission,
      :invalid_github_recipient,
      :forbidden,
      :unauthorized
    ]
  end

  defp failure_code(reason)
       when reason in [
              :repository_name_taken,
              :repository_identity_mismatch,
              :repository_identity_conflict
            ],
       do: "repository_conflict"

  defp failure_code(reason) when reason in [:forbidden, :unauthorized, :invalid_permission],
    do: "permission_denied"

  defp failure_code(:invalid_github_recipient), do: "collaborator_setup_failed"

  defp failure_code(reason)
       when reason in [
              :workflow_already_exists,
              :missing_autograding_tests,
              :invalid_autograding_tests,
              :invalid_autograding_config
            ],
       do: "workflow_setup_failed"

  defp failure_code(_reason), do: "github_unavailable"
end
