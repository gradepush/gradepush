defmodule GradePushWeb.GradingComponents do
  @moduledoc false
  use GradePushWeb, :html

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
    <section id={@id} class="cp-grading" aria-label={gettext("Automatic test results")}>
      <div class="cp-grading-summary">
        <p :if={@grade && !@untrusted?} class="cp-grading-total">
          {gettext("Test score")} <strong>{points(@grade.score)} / {points(@grade.max_score)}</strong>
        </p>
        <p :if={@untrusted?} role="status" class="cp-grading-warning">
          {gettext("The grading workflow changed. This result cannot be verified.")}
        </p>
        <p :if={!@grade} role="status">
          {waiting_message(@subject, @push)}
        </p>
        <p :if={@push} class="cp-grading-commit">
          {if @grade && !@untrusted?, do: gettext("Assessed commit"), else: gettext("Latest commit")}
          <code title={@push.commit_sha}>{String.slice(@push.commit_sha, 0, 7)}</code>
        </p>
        <a
          :if={@actions_url}
          href={@actions_url}
          target="_blank"
          rel="noopener noreferrer"
          class="cp-repo-link"
        >
          <.icon name="hero-arrow-top-right-on-square" class="size-4" />{gettext(
            "View GitHub Actions"
          )}
        </a>
      </div>
      <ul class="cp-test-list cp-test-list-embedded">
        <li :for={test <- @tests} id={"#{@id}-test-#{test.id}"}>
          <% result = Map.get(@results, test.id) %>
          <div class="cp-grading-description">
            <h3>{test.name}</h3><p :if={test.description not in [nil, ""]}>{test.description}</p>
          </div>
          <div class="cp-grading-outcome">
            <span class={["cp-grading-status", result && "cp-grading-#{result.status}"]}>
              {status_label(result, @untrusted?, @push)}
            </span>
            <span :if={result}>{points(result.points_awarded)} / {points(result.max_points)}</span>
            <span :if={!result}>{gettext("%{points} points", points: points(test.points))}</span>
          </div>
        </li>
      </ul>
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

  defp points(%Decimal{} = value), do: value |> Decimal.normalize() |> Decimal.to_string(:normal)
  defp points(value), do: to_string(value)

  defp actions_url(%{html_url: "https://github.com/" <> _ = url}, _), do: url

  defp actions_url(_, %{repository: %{html_url: "https://github.com/" <> _ = url}}),
    do: url <> "/actions"

  defp actions_url(_, _), do: nil
end
