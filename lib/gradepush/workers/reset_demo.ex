defmodule GradePush.Workers.ResetDemo do
  @moduledoc "Resets the isolated demo installation on its scheduled interval."

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    GradePush.Demo.reset(job_id: job_id)
  end
end
