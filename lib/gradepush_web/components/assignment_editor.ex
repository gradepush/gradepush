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
      "max-[600px]:[&_[data-ui~=test-name-row]]:grid-cols-[minmax(0,1fr)_80px]",
      "max-[600px]:[&_[data-ui~=test-name-row]]:gap-[12px]"
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
          <fieldset disabled={@locked and not @demo} aria-labelledby="assignment-grading">
            <.input
              field={@form[:autograding]}
              type="checkbox"
              label={gettext("Enable automatic tests")}
            />
            <div :if={@form[:autograding].value in [true, "true"]}>
              <.field_hint>
                {gettext(
                  "GitHub Actions runs these tests on each push. Points are added for each successful test."
                )}
              </.field_hint>
              <.inputs_for :let={test} field={@form[:tests]}>
                <fieldset class={[
                  "border border-line rounded-[9px] min-w-0 p-[18px] my-[20px] mx-0 [&_legend]:text-[13px]",
                  "[&_legend]:font-semibold [&_legend]:py-0 [&_legend]:px-[7px]"
                ]}>
                  <legend>{gettext("Test %{number}", number: test.index + 1)}</legend>
                  <div
                    data-ui="form-grid test-name-row"
                    class="grid grid-cols-[minmax(0,1fr)_100px] gap-[16px]"
                  >
                    <.input field={test[:name]} label={gettext("Test name")} required maxlength="120" />
                    <.input
                      field={test[:points]}
                      type="number"
                      label={gettext("Points")}
                      min="1"
                      max="1000"
                      required
                    />
                  </div>
                  <.input
                    field={test[:description]}
                    type="textarea"
                    label={gettext("Description")}
                    rows="2"
                    maxlength="2000"
                  />
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
                    :if={test[:type].value == "file"}
                    field={test[:path]}
                    label={gettext("File path")}
                    placeholder="src/main.py"
                    required
                  />
                  <.input
                    :if={test[:type].value != "file"}
                    field={test[:command]}
                    label={gettext("Command")}
                    placeholder="python -m unittest"
                    required
                  />
                  <div
                    :if={test[:type].value == "io"}
                    data-ui="form-grid"
                    class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-[16px]"
                  >
                    <.input
                      field={test[:input]}
                      type="textarea"
                      label={gettext("Standard input (optional)")}
                      rows="3"
                    />
                    <.input
                      field={test[:expected]}
                      type="textarea"
                      label={gettext("Expected output")}
                      rows="3"
                      required
                    />
                  </div>
                  <.field_hint :if={test[:type].value == "io"}>
                    {gettext("The output must match exactly, including whitespace.")}
                  </.field_hint>
                  <.button
                    type="button"
                    variant="text-danger"
                    phx-click="remove_assignment_test"
                    phx-value-index={test.index}
                  ><.icon name="hero-trash" class="size-4" />{gettext("Remove test")}</.button>
                </fieldset>
              </.inputs_for>
              <div class="flex items-center justify-between mb-[16px] gap-[16px] [&>span]:text-[12px] [&>span]:text-muted">
                <.button type="button" phx-click="add_assignment_test"><.icon
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
