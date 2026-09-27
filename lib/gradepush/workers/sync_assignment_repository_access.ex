defmodule GradePush.Workers.SyncAssignmentRepositoryAccess do
  @moduledoc "Reconciles collaborators for an existing assignment repository."

  use Oban.Worker, queue: :github, max_attempts: 10

  alias GradePush.Assignments
  alias GradePush.GitHub.RepositoryAccess

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subject_id" => subject_id}} = job) do
    case Assignments.provisioning_intent(subject_id) do
      {:ok, intent} -> sync_ready_repository(intent, job)
      {:error, reason} when reason in [:no_github_recipients, :not_found] -> :ok
      {:error, reason} -> retry_or_fail(subject_id, job, reason)
    end
  end

  def perform(_job), do: :ok

  defp sync_ready_repository(intent, job) do
    repository = value(intent, :repository) || %{}

    case value(repository, :state) do
      "ready" ->
        sync_ready_recipients(intent, repository, job)

      "pending" ->
        retry_or_fail(value(intent, :subject_id), job, :repository_not_ready)

      _state ->
        :ok
    end
  end

  defp sync_ready_recipients(intent, repository, job) do
    subject_id = value(intent, :subject_id)
    recipients = value(intent, :recipients)

    if valid_recipients?(recipients) do
      result =
        RepositoryAccess.sync_collaborators(
          value(intent, :installation_id),
          value(repository, :github_repository_id),
          value(repository, :owner_login),
          value(repository, :name),
          recipients
        )

      case result do
        :ok -> :ok
        {:error, reason} -> retry_or_fail(subject_id, job, reason)
      end
    else
      :ok
    end
  end

  defp retry_or_fail(subject_id, job, reason) do
    if permanent_failure?(reason) or job.attempt >= job.max_attempts do
      Assignments.repository_provisioning_failed(subject_id, "collaborator_setup_failed")
      {:discard, "collaborator_setup_failed"}
    else
      {:error, reason}
    end
  end

  defp permanent_failure?(reason) do
    reason in [
      :invalid_repository,
      :invalid_github_recipient,
      :invalid_permission,
      :forbidden,
      :unauthorized
    ]
  end

  defp valid_recipients?(recipients), do: is_list(recipients) and recipients != []

  defp value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp value(_map, _key), do: nil
end
