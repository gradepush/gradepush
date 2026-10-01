defmodule GradePushWeb.GradingComponents do
  @moduledoc false
  use GradePushWeb, :html

  import GradePushWeb.Presentation, only: [points: 1]

  attr :id, :string, required: true
  attr :tests, :list, required: true
  attr :subject, :any, default: nil

  def results(assigns) do
    grade = assigns.subject && assigns.subject.latest_grade
    push = assigns.subject && assigns.subject.latest_push
    untrusted? = match?(%{status: "untrusted"}, grade)

    results =
      if grade && !untrusted?,
        do: Map.new(grade.tests, &{&1.assignment_test_id, &1}),
        else: %{}

    assigns =
      assign(assigns,
        grade: grade,
        push: push,
        untrusted?: untrusted?,
        results: results,
        actions_url: actions_url(grade, assigns.subject)
      )

    ~H"""
    <section
      data-ui="grading"
      id={@id}
      aria-label={gettext("Automatic test results")}
    >
      <div
        data-ui="grading-summary"
        class={[
          "flex flex-wrap items-center gap-y-[12px] gap-x-[24px] border-b border-b-line text-[13px] text-muted p-[22px]",
          "[&>p:first-child]:basis-full max-[640px]:p-[18px] max-[640px]:gap-[12px]"
        ]}
      >
        <p
          :if={@grade && !@untrusted?}
          data-ui="grading-total"
          class="[&_strong]:ml-[8px] [&_strong]:text-[18px] [&_strong]:text-ink"
        >
          {gettext("Test score")} <strong>{points(@grade.score)} / {points(@grade.max_score)}</strong>
        </p>
        <p :if={@untrusted?} data-ui="grading-warning" role="status" class="text-failure">
          {gettext("The grading workflow changed. This result cannot be verified.")}
        </p>
        <p :if={!@grade} role="status">
          {waiting_message(@subject, @push)}
        </p>
        <p
          :if={@push}
          class="flex items-center gap-[8px] [&_code]:text-ink"
        >
          {if @grade && !@untrusted?, do: gettext("Assessed commit"), else: gettext("Latest commit")}
          <code title={@push.commit_sha}>{String.slice(@push.commit_sha, 0, 7)}</code>
        </p>
        <a
          :if={@actions_url}
          href={@actions_url}
          target="_blank"
          rel="noopener noreferrer"
          class={[
            "inline-flex items-center whitespace-nowrap border-0 bg-transparent py-[4px] px-0 gap-[6px]",
            "disabled:opacity-[1] disabled:text-muted"
          ]}
        >
          <.icon name="hero-arrow-top-right-on-square" class="size-4" />{gettext(
            "View GitHub Actions"
          )}
        </a>
        <p
          :if={@actions_url && Enum.any?(@tests, &(&1.type == "io"))}
          class="basis-full text-[12px] leading-[1.6]"
        >
          {gettext(
            "Input/output logs on GitHub Actions show expected and actual output. Exact and trailing-whitespace comparisons also show differences."
          )}
        </p>
      </div>
      <.test_list embedded>
        <li :for={test <- @tests} id={"#{@id}-test-#{test.id}"}>
          <% result = Map.get(@results, test.id) %>
          <div class="min-w-0 wrap-anywhere">
            <h3>{test.name}</h3><p :if={test.description not in [nil, ""]}>{test.description}</p>
          </div>
          <div class={[
            "flex flex-col items-end text-[13px] whitespace-nowrap tabular-nums text-muted gap-[6px] max-[640px]:w-full",
            "max-[640px]:flex-row max-[640px]:items-center max-[640px]:justify-between max-[640px]:gap-[12px]"
          ]}>
            <span
              data-ui="grading-status"
              data-result={result && result.status}
              class={[
                "font-semibold",
                case result && result.status do
                  "success" -> "text-success"
                  "failure" -> "text-failure"
                  _ -> "text-ink"
                end
              ]}
            >
              {status_label(result, @untrusted?, @push)}
            </span>
            <span :if={result}>{points(result.points_awarded)} / {points(result.max_points)}</span>
            <span :if={!result}>{gettext("%{points} points", points: points(test.points))}</span>
          </div>
        </li>
      </.test_list>
    </section>
    """
  end

  defp status_label(_, true, _), do: gettext("Not verified")
  defp status_label(%{status: "success"}, _, _), do: gettext("Passed")
  defp status_label(%{status: "failure"}, _, _), do: gettext("Failed")
  defp status_label(%{status: "cancelled"}, _, _), do: gettext("Cancelled")
  defp status_label(%{status: "skipped"}, _, _), do: gettext("Skipped")
  defp status_label(nil, _, nil), do: gettext("Not run")
  defp status_label(_, _, _), do: gettext("Awaiting results")

  defp waiting_message(nil, _),
    do: gettext("Accept the assignment to run these tests in your repository.")

  defp waiting_message(_, nil), do: gettext("No results yet. Push your work to run the tests.")
  defp waiting_message(_, _), do: gettext("Awaiting results for the latest push.")

  defp actions_url(%{html_url: "https://github.com/" <> _ = url}, _), do: url

  defp actions_url(_, %{repository: %{html_url: "https://github.com/" <> _ = url}}),
    do: url <> "/actions"

  defp actions_url(_, _), do: nil
end
