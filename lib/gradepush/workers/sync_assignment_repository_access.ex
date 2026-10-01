defmodule GradePush.Workers.SyncAssignmentRepositoryAccess do
  @moduledoc "Reconciles collaborators for an existing assignment repository."

  use Oban.Worker, queue: :github, max_attempts: 10

  alias GradePush.Assignments
  alias GradePush.GitHub.RepositoryAccess

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subject_id" => subject_id}} = job) do
    case RepositoryAccess.sync_subject(subject_id) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> retry_or_fail(subject_id, job, reason)
    end
  end

  def perform(_job), do: :ok

  defp retry_or_fail(subject_id, job, reason) do
    if permanent_failure?(reason) or job.attempt >= job.max_attempts do
      Assignments.repository_access_failed(subject_id)
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
end
