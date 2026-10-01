defmodule GradePushWeb.AssignmentEditor do
  @moduledoc false
  use GradePushWeb, :html

  alias GradePushWeb.ClassroomComponents

  attr :form, Phoenix.HTML.Form, required: true
  attr :classroom, :map, required: true
  attr :assignment, :any, default: nil
  attr :locale, :string, required: true
  attr :templates, :list, required: true
  attr :preview, :boolean, default: false
  attr :demo, :boolean, default: true

  def page(assigns) do
    assigns =
      assign(assigns, :locked, assigns.assignment != nil and assigns.assignment.submitted > 0)

    ~H"""
    <div class={[
      "max-[600px]:[&_[data-ui~=form-grid]]:grid-cols-[minmax(0,1fr)] max-[600px]:[&_[data-ui~=form-grid]]:gap-0",
      "max-[760px]:[&_[data-ui~=test-name-fields]]:flex-1",
      "max-[600px]:[&_[data-ui~=test-name-fields]]:grid-cols-[minmax(0,1fr)_76px] max-[600px]:[&_[data-ui~=test-name-fields]]:gap-[8px]",
      "max-[420px]:[&_[data-ui~=test-name-fields]]:grid-cols-[minmax(0,1fr)] max-[420px]:[&_[data-ui~=test-name-fields]]:gap-0"
    ]}>
      <ClassroomComponents.breadcrumbs items={breadcrumb_items(@classroom, @assignment, @locale)} />
      <.page_heading>
        <div>
          <h1>
            {if @assignment, do: gettext("Edit assignment"), else: gettext("New assignment")}
          </h1>
        </div>
      </.page_heading>
      <.form
        for={@form}
        id="assignment-form"
        phx-change="validate_assignment"
        phx-submit="save_assignment"
        class="[&_.ui-field]:mb-[18px] [&_.ui-field]:min-w-0"
      >
        <.notice
          :if={@form.source.action == :insert and not @form.source.valid?}
          kind="error"
          role="alert"
        >
          {gettext("Check the highlighted fields before saving.")}
        </.notice>
        <.form_section aria-label={gettext("Assignment details")}>
          <.input field={@form[:title]} label={gettext("Title")} required maxlength="120" />
          <div class="flex items-center justify-between gap-[16px] mb-[8px]">
            <.field for={@form[:instructions].id}>{gettext("Instructions (Markdown)")}</.field>
            <.button
              type="button"
              variant="text"
              phx-click="toggle_instructions_preview"
              aria-pressed={to_string(@preview)}
            >{if @preview, do: gettext("Write"), else: gettext("Preview")}</.button>
          </div>
          <div
            :if={@preview}
            class="min-h-[210px] rounded-[7px] border border-[#d7deea] p-[18px] mb-[18px] wrap-anywhere markdown"
            role="region"
            aria-label={gettext("Instructions preview")}
          >
            <.field_hint :if={@form[:instructions].value in [nil, ""]}>
              {gettext("Write instructions to see the preview.")}
            </.field_hint>
            <h2 class="sr-only">{gettext("Instructions preview")}</h2>
            {GradePushWeb.Markdown.render(@form[:instructions].value || "", 2)}
          </div>
          <div hidden={@preview}>
            <.input
              field={@form[:instructions]}
              type="textarea"
              rows="7"
              maxlength="20000"
              aria-label={gettext("Instructions (Markdown)")}
            />
          </div>
          <div data-ui="form-grid" class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-[16px]">
            <.input
              field={@form[:kind]}
              type="select"
              label={gettext("Work type")}
              options={[{gettext("Individual"), "individual"}, {gettext("Team"), "team"}]}
              disabled={@locked}
            />
            <div>
              <.input
                field={@form[:deadline]}
                type="datetime-local"
                label={gettext("Deadline (optional)")}
              />
              <.input
                field={@form[:cutoff]}
                type="checkbox"
                label={gettext("Block pushes after the deadline")}
                disabled={not @demo or @form[:deadline].value in [nil, ""]}
                checked={
                  @form[:deadline].value not in [nil, ""] and @form[:cutoff].value in [true, "true"]
                }
              />
              <.field_hint :if={!@demo}>
                {gettext("Hard cutoffs are unavailable for connected GitHub repositories.")}
              </.field_hint>
            </div>
          </div>
          <div
            :if={@form[:kind].value == "team"}
            data-ui="form-grid"
            class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-[16px]"
          >
            <.input
              field={@form[:team_mode]}
              type="select"
              label={gettext("Team formation")}
              options={[
                {gettext("Students create or join a team"), "students"},
                {gettext("Teacher assigns teams"), "teacher"}
              ]}
              disabled={@locked}
            />
            <.input
              field={@form[:team_size]}
              type="number"
              label={gettext("Maximum students per team")}
              min="2"
              max="20"
              disabled={@locked}
            />
          </div>
        </.form_section>
        <.form_section aria-labelledby="assignment-repository">
          <h2 id="assignment-repository">{gettext("Repository")}</h2>
          <.field_hint>
            {gettext("Repositories will be created in %{organization}.",
              organization: @classroom.organization
            )}
          </.field_hint>
          <.input
            field={@form[:template]}
            label={gettext("Starter template (optional)")}
            list="assignment-templates"
            placeholder={gettext("Search templates in this organization")}
            disabled={@locked}
            autocomplete="off"
          />
          <datalist id="assignment-templates"><option :for={template <- @templates} value={template} /></datalist>
          <.field_hint :if={@locked}>
            {gettext("The template and work type are fixed once students have accepted.")}
          </.field_hint>
        </.form_section>
        <.form_section aria-labelledby="assignment-grading">
          <h2 id="assignment-grading">{gettext("Automatic tests")}</h2>
          <.field_hint :if={@locked and not @demo}>
            {gettext("Automatic tests are fixed once students have accepted.")}
          </.field_hint>
          <fieldset aria-labelledby="assignment-grading">
            <div
              data-ui="grading-toggle"
              class="[&>.ui-field]:flex [&>.ui-field]:flex-wrap [&>.ui-field]:items-center [&>.ui-field]:gap-x-[20px] [&>.ui-field]:gap-y-[8px] [&_.ui-field>div>p]:mt-0"
            >
              <.input
                field={@form[:autograding]}
                type="checkbox"
                label={gettext("Enable automatic tests")}
                disabled={@locked and not @demo}
              />
            </div>
            <div :if={@form[:autograding].value in [true, "true"]}>
              <.field_hint>
                {gettext(
                  "GitHub Actions runs these tests on each push. Points are added for each successful test."
                )}
              </.field_hint>
              <.inputs_for :let={test} field={@form[:tests]} skip_hidden={@locked and not @demo}>
                <section
                  id={test.id <> "-card"}
                  phx-hook="TestCardDisclosure"
                  aria-labelledby={test.id <> "-toggle"}
                  data-expanded="true"
                  data-has-errors={test_errors?(test)}
                  class="group min-w-0 overflow-hidden rounded-[9px] border border-line bg-white my-[20px]"
                  data-ui="automatic-test"
                >
                  <div
                    data-ui="test-card-heading"
                    class="flex items-stretch bg-surface-heading group-data-[expanded=true]:border-b group-data-[expanded=true]:border-line"
                  >
                    <button
                      id={test.id <> "-toggle"}
                      type="button"
                      data-test-toggle
                      aria-expanded="true"
                      aria-controls={test.id <> "-settings"}
                      class="flex min-h-[64px] min-w-0 flex-1 cursor-pointer items-center gap-[12px] px-[18px] py-[14px] text-left hover:bg-brand/5 focus-visible:outline-2 focus-visible:outline-offset-[-3px] focus-visible:outline-brand"
                    >
                      <span class="min-w-0 flex-1">
                        <span class="block text-[12px] text-muted">
                          {gettext("Test %{number}", number: test.index + 1)}
                        </span>
                        <span
                          data-test-name
                          class="block text-[14px] font-semibold text-ink [overflow-wrap:anywhere]"
                        >
                          {if test[:name].value in [nil, ""],
                            do: gettext("Untitled test"),
                            else: test[:name].value}
                        </span>
                      </span>
                      <span data-test-points class="shrink-0 text-[12px] font-medium text-muted">
                        {gettext("%{points} points", points: test[:points].value || 0)}
                      </span>
                      <span data-test-collapse><.icon
                        name="hero-chevron-up"
                        class="size-5 text-muted"
                      /></span>
                      <span data-test-expand hidden><.icon
                        name="hero-chevron-down"
                        class="size-5 text-muted"
                      /></span>
                    </button>
                    <.button
                      type="button"
                      variant="text-danger"
                      class="mr-[14px] h-[44px] w-[44px] shrink-0 self-center justify-center rounded-md border border-danger/30 bg-danger/5 text-danger hover:bg-danger/10"
                      phx-click="remove_assignment_test"
                      phx-value-index={test.index}
                      disabled={@locked and not @demo}
                      aria-label={gettext("Remove test %{number}", number: test.index + 1)}
                      title={gettext("Remove test")}
                    ><.icon name="hero-trash" class="size-5" /></.button>
                  </div>
                  <fieldset
                    id={test.id <> "-settings"}
                    data-test-settings
                    class="min-w-0 p-[18px]"
                    disabled={@locked and not @demo}
                  >
                    <input
                      :for={field <- hidden_test_fields(test[:type].value)}
                      id={test[field].id <> "-inactive"}
                      type="hidden"
                      name={test[field].name}
                      value={test[field].value}
                    />
                    <div
                      id={test.id <> "-identity-row"}
                      data-ui="test-name-row"
                      class="flex items-start justify-between gap-[16px]"
                    >
                      <fieldset
                        id={test.id <> "-identity-fields"}
                        data-ui="test-name-fields"
                        class="grid w-1/2 min-w-0 grid-cols-[minmax(0,1fr)_100px] gap-[16px]"
                        disabled={@locked and not @demo}
                      >
                        <.input
                          field={test[:name]}
                          label={gettext("Test name")}
                          required
                          maxlength="120"
                        />
                        <.input
                          field={test[:points]}
                          type="number"
                          label={gettext("Points")}
                          phx-debounce="blur"
                          min="1"
                          max="1000"
                          required
                        />
                      </fieldset>
                    </div>
                    <.input
                      field={test[:description]}
                      type="textarea"
                      label={gettext("Description (optional)")}
                      placeholder={gettext("Explain what this test checks.")}
                      rows="2"
                      maxlength="2000"
                    />
                    <div
                      id={test.id <> "-type"}
                      data-ui="form-grid"
                      class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-[16px]"
                    >
                      <.input
                        field={test[:type]}
                        type="select"
                        label={gettext("Test type")}
                        options={[
                          {gettext("Command succeeds"), "command"},
                          {gettext("File exists"), "file"},
                          {gettext("Input / output"), "io"}
                        ]}
                      />
                      <.input
                        :if={test[:type].value != "file"}
                        field={test[:runtime]}
                        type="select"
                        label={gettext("Execution environment")}
                        options={runtime_options()}
                      />
                    </div>
                    <.input
                      :if={test[:type].value == "file"}
                      field={test[:path]}
                      label={gettext("File path")}
                      placeholder="src/main.py"
                      required
                    />
                    <.input
                      :if={test[:type].value != "file"}
                      field={test[:setup_command]}
                      label={gettext("Preparation command (optional)")}
                      placeholder={setup_placeholder(test[:runtime].value)}
                      maxlength="100000"
                    />
                    <.field_hint :if={test[:type].value != "file"}>
                      {gettext(
                        "Install dependencies or compile the program here. If preparation fails, the test fails."
                      )}
                    </.field_hint>
                    <.input
                      :if={test[:type].value != "file"}
                      field={test[:command]}
                      label={gettext("Run command")}
                      placeholder={command_placeholder(test[:runtime].value, test[:type].value)}
                      maxlength="100000"
                      required
                    />
                    <div
                      :if={test[:type].value == "io"}
                      id={test.id <> "-io"}
                      data-ui="form-grid"
                      class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-[16px]"
                    >
                      <.input
                        field={test[:input]}
                        type="textarea"
                        label={gettext("Standard input (optional)")}
                        rows="3"
                        class="font-mono"
                        maxlength="100000"
                      />
                      <.input
                        field={test[:expected]}
                        type="textarea"
                        label={
                          if test[:output_comparison].value == "regex",
                            do: gettext("Expected pattern"),
                            else: gettext("Expected output")
                        }
                        rows="3"
                        class="font-mono"
                        aria-describedby={
                          if test[:output_comparison].value == "regex",
                            do: test.id <> "-comparison-hint"
                        }
                        maxlength={
                          if test[:output_comparison].value == "regex", do: "4096", else: "100000"
                        }
                        required
                      />
                    </div>
                    <div
                      :if={test[:type].value != "file"}
                      id={test.id <> "-limits"}
                      data-ui="form-grid"
                      class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-[16px]"
                    >
                      <div :if={test[:type].value == "io"}>
                        <.input
                          field={test[:output_comparison]}
                          type="select"
                          label={gettext("Output comparison")}
                          aria-describedby={test.id <> "-comparison-hint"}
                          options={[
                            {gettext("Ignore trailing whitespace"), "trim_trailing"},
                            {gettext("Exact match"), "exact"},
                            {gettext("Contains expected output"), "contains"},
                            {gettext("Regular expression"), "regex"}
                          ]}
                        />
                        <.field_hint id={test.id <> "-comparison-hint"}>
                          <strong
                            :if={test[:output_comparison].value == "regex"}
                            class="mb-1 block font-semibold text-ink"
                          >
                            {gettext("Enter the regular expression in “Expected pattern”.")}
                          </strong>
                          {comparison_hint(test[:output_comparison].value)}
                        </.field_hint>
                      </div>
                      <div>
                        <.input
                          field={test[:timeout_seconds]}
                          type="number"
                          label={gettext("Time limit per command (seconds)")}
                          min="30"
                          max="1200"
                          required
                        />
                        <.field_hint>
                          {gettext("Allow 30 to 1200 seconds for each command. Default: 300 seconds.")}
                        </.field_hint>
                      </div>
                    </div>
                  </fieldset>
                </section>
              </.inputs_for>
              <div class="flex items-center justify-between mb-[16px] gap-[16px] [&>span]:text-[12px] [&>span]:text-muted">
                <.button
                  type="button"
                  variant="secondary"
                  phx-click="add_assignment_test"
                  disabled={@locked and not @demo}
                ><.icon
                  name="hero-plus"
                  class="size-4"
                />{gettext("Add test")}</.button>
                <span>{gettext("%{points} points total", points: total(@form))}</span>
              </div>
            </div>
          </fieldset>
        </.form_section>
        <div
          data-ui="editor-actions"
          class="flex justify-end pt-[4px] gap-[12px] max-[600px]:justify-stretch max-[600px]:[&>*]:flex-1"
        >
          <.button patch={back_path(@classroom, @assignment)}>{gettext("Cancel")}</.button>
          <.button type="submit" variant="primary" phx-disable-with={gettext("Saving…")}>{if @assignment,
            do: gettext("Save changes"),
            else: gettext("Create assignment")}</.button>
        </div>
      </.form>
    </div>
    """
  end

  defp runtime_options do
    [
      {gettext("Shell / custom command"), "system"},
      {"Python 3.14.7", "python-3.14.7"},
      {"Node.js 24.21.0 LTS", "node-24.21.0"},
      {"PHP 8.5.11", "php-8.5.11"},
      {"Java 25 LTS", "java-25"},
      {"C / C++ (GCC 14)", "c-cpp-14"}
    ]
  end

  defp hidden_test_fields("io"), do: [:path]

  defp hidden_test_fields("file"),
    do: [
      :runtime,
      :timeout_seconds,
      :setup_command,
      :command,
      :input,
      :expected,
      :output_comparison
    ]

  defp hidden_test_fields(_), do: [:path, :input, :expected, :output_comparison]

  defp test_errors?(test) do
    Enum.any?(
      ~w(name description type points runtime setup_command command path input expected output_comparison timeout_seconds)a,
      fn field ->
        Phoenix.Component.used_input?(test[field]) and test[field].errors != []
      end
    )
  end

  defp setup_placeholder("python-" <> _), do: "pip install -r requirements.txt"
  defp setup_placeholder("node-" <> _), do: "npm ci"
  defp setup_placeholder("php-" <> _), do: "composer install --no-interaction"
  defp setup_placeholder("java-25"), do: "javac Main.java"
  defp setup_placeholder("c-cpp-14"), do: "gcc -Wall -Wextra main.c -o main"
  defp setup_placeholder(_), do: gettext("Leave empty if no preparation is needed.")

  defp command_placeholder("python-" <> _, "io"), do: "python main.py"
  defp command_placeholder("python-" <> _, _), do: "python -m unittest"
  defp command_placeholder("node-" <> _, "io"), do: "node main.js"
  defp command_placeholder("node-" <> _, _), do: "npm test"
  defp command_placeholder("php-" <> _, _), do: "php main.php"
  defp command_placeholder("java-25", _), do: "java Main"
  defp command_placeholder("c-cpp-14", _), do: "./main"
  defp command_placeholder(_, _), do: "bash test.sh"

  defp comparison_hint("exact"), do: gettext("All spaces and line breaks must match exactly.")

  defp comparison_hint("contains"),
    do: gettext("The expected text must appear anywhere in the output.")

  defp comparison_hint("regex"),
    do:
      gettext(
        "Use a JavaScript regular expression without / delimiters. It matches anywhere in the output; use ^ and $ to anchor it."
      )

  defp comparison_hint(_),
    do:
      gettext(
        "Ignore spaces and tabs at line ends and final line breaks. Keep leading spaces, spaces within lines and empty lines within the output."
      )

  defp total(form) do
    form.source |> Ecto.Changeset.get_field(:tests, []) |> Enum.sum_by(&(&1.points || 0))
  end

  defp breadcrumb_items(classroom, assignment, locale) do
    language = String.to_existing_atom(locale)

    parents = [
      {gettext("Classrooms"), "/classrooms"},
      {Map.fetch!(classroom.title, language), "/classrooms/#{classroom.slug}"}
    ]

    if assignment do
      parents ++
        [
          {Map.fetch!(assignment.title, language), back_path(classroom, assignment)},
          {gettext("Edit assignment"), nil}
        ]
    else
      parents ++ [{gettext("New assignment"), nil}]
    end
  end

  defp back_path(classroom, nil), do: "/classrooms/#{classroom.slug}"

  defp back_path(classroom, assignment),
    do: "/classrooms/#{classroom.slug}/assignments/#{assignment.key}"
end
