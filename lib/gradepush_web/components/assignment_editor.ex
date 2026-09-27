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
    <div class="cp-editor">
      <ClassroomComponents.breadcrumbs items={breadcrumb_items(@classroom, @assignment, @locale)} />
      <div class="cp-heading cp-editor-heading">
        <div>
          <h1>
            {if @assignment, do: gettext("Edit assignment"), else: gettext("New assignment")}
          </h1>
        </div>
      </div>
      <.form
        for={@form}
        id="assignment-form"
        phx-change="validate_assignment"
        phx-submit="save_assignment"
        class="cp-editor-form"
      >
        <p
          :if={@form.source.action == :insert and not @form.source.valid?}
          class="cp-error"
          role="alert"
        >
          {gettext("Check the highlighted fields before saving.")}
        </p>
        <section class="cp-form-section cp-form-basics" aria-label={gettext("Assignment details")}>
          <.input field={@form[:title]} label={gettext("Title")} required maxlength="120" />
          <div class="cp-markdown-heading">
            <label for={@form[:instructions].id}>{gettext("Instructions (Markdown)")}</label>
            <button
              type="button"
              class="cp-text-button"
              phx-click="toggle_instructions_preview"
              aria-pressed={to_string(@preview)}
            >{if @preview, do: gettext("Write"), else: gettext("Preview")}</button>
          </div>
          <div
            :if={@preview}
            class="cp-markdown-preview cp-markdown"
            role="region"
            aria-label={gettext("Instructions preview")}
          >
            <p :if={@form[:instructions].value in [nil, ""]} class="cp-field-help">
              {gettext("Write instructions to see the preview.")}
            </p>
            {GradePushWeb.Markdown.render(@form[:instructions].value || "")}
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
          <div class="cp-form-grid cp-work-deadline">
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
              <p :if={!@demo} class="cp-field-help">
                {gettext("Hard cutoffs are unavailable for connected GitHub repositories.")}
              </p>
            </div>
          </div>
          <div :if={@form[:kind].value == "team"} class="cp-form-grid">
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
        </section>
        <section class="cp-form-section" aria-labelledby="assignment-repository">
          <h2 id="assignment-repository">{gettext("Repository")}</h2>
          <p class="cp-field-help">
            {gettext("Repositories will be created in %{organization}.",
              organization: @classroom.organization
            )}
          </p>
          <.input
            field={@form[:template]}
            label={gettext("Starter template (optional)")}
            list="assignment-templates"
            placeholder={gettext("Search templates in this organization")}
            disabled={@locked}
            autocomplete="off"
          />
          <datalist id="assignment-templates"><option :for={template <- @templates} value={template} /></datalist>
          <p :if={@locked} class="cp-field-help">
            {gettext("The template and work type are fixed once students have accepted.")}
          </p>
        </section>
        <section class="cp-form-section" aria-labelledby="assignment-grading">
          <h2 id="assignment-grading">{gettext("Automatic tests")}</h2>
          <p :if={@locked and not @demo} class="cp-field-help">
            {gettext("Automatic tests are fixed once students have accepted.")}
          </p>
          <fieldset disabled={@locked and not @demo} aria-labelledby="assignment-grading">
            <.input
              field={@form[:autograding]}
              type="checkbox"
              label={gettext("Enable automatic tests")}
            />
            <div :if={@form[:autograding].value in [true, "true"]}>
              <p class="cp-field-help">
                {gettext(
                  "GitHub Actions runs these tests on each push. Points are added for each successful test."
                )}
              </p>
              <.inputs_for :let={test} field={@form[:tests]}>
                <fieldset class="cp-test-editor">
                  <legend>{gettext("Test %{number}", number: test.index + 1)}</legend>
                  <div class="cp-form-grid cp-test-name-row">
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
                  <div :if={test[:type].value == "io"} class="cp-form-grid">
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
                  <p :if={test[:type].value == "io"} class="cp-field-help">
                    {gettext("The output must match exactly, including whitespace.")}
                  </p>
                  <button
                    type="button"
                    class="cp-text-button cp-remove-test"
                    phx-click="remove_assignment_test"
                    phx-value-index={test.index}
                  ><.icon name="hero-trash" class="size-4" />{gettext("Remove test")}</button>
                </fieldset>
              </.inputs_for>
              <div class="cp-test-editor-footer">
                <button type="button" class="cp-button" phx-click="add_assignment_test"><.icon
                  name="hero-plus"
                  class="size-4"
                />{gettext("Add test")}</button>
                <span>{gettext("%{points} points total", points: total(@form))}</span>
              </div>
            </div>
          </fieldset>
        </section>
        <div class="cp-editor-actions">
          <.link patch={back_path(@classroom, @assignment)} class="cp-button">{gettext("Cancel")}</.link>
          <button type="submit" class="cp-button cp-primary" phx-disable-with={gettext("Saving…")}>{if @assignment,
            do: gettext("Save changes"),
            else: gettext("Create assignment")}</button>
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
