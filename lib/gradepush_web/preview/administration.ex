defmodule GradePushWeb.Preview.Administration do
  @moduledoc "Transient administration scenarios. Does not grant real access or change server configuration."
  use Gettext, backend: GradePushWeb.Gettext

  def initial do
    %{
      name: "Cégep de Sorel-Tracy",
      teachers: [
        %{id: "jordan", name: "Jordan Rioux", handle: "mrjordash", initials: "JR", admin?: true},
        %{
          id: "camille",
          name: "Camille Bergeron",
          handle: "camille-bergeron",
          initials: "CB",
          admin?: true
        },
        %{id: "alex", name: "Alex Nguyen", handle: "alex-nguyen", initials: "AN", admin?: false},
        %{
          id: "sophie",
          name: "Sophie Gagnon",
          handle: "sophie-gagnon",
          initials: "SG",
          admin?: false
        }
      ],
      classrooms: [
        %{
          id: "programming",
          title: %{en: "Programming I", fr: "Programmation I"},
          code: "420-110",
          students: 28,
          teachers: ["jordan", "camille"]
        },
        %{
          id: "web",
          title: %{en: "Web Development", fr: "Développement Web"},
          code: "420-210",
          students: 24,
          teachers: ["jordan", "camille"]
        },
        %{
          id: "data",
          title: %{en: "Data Structures", fr: "Structures de données"},
          code: "420-310",
          students: 18,
          teachers: ["jordan"]
        },
        %{
          id: "databases",
          title: %{en: "Databases", fr: "Bases de données"},
          code: "420-410",
          students: 22,
          teachers: ["alex"]
        }
      ],
      students: 54,
      history: [
        %{
          actor: "Camille Bergeron",
          action: gettext("Teacher added to classroom"),
          target: "Alex Nguyen · 420-410",
          time: "2026-09-25 10:42"
        },
        %{
          actor: "Jordan Rioux",
          action: gettext("Institution administrator appointed"),
          target: "Camille Bergeron",
          time: "2026-09-24 14:18"
        }
      ]
    }
  end

  def teacher(state, id), do: Enum.find(state.teachers, &(&1.id == id))
  def classroom(state, id), do: Enum.find(state.classrooms, &(&1.id == id))
  def class_count(state, id), do: Enum.count(state.classrooms, &(id in &1.teachers))

  def candidates(state, classroom, actor_id) do
    Enum.reject(state.teachers, &(&1.id == actor_id or &1.id in classroom.teachers))
  end

  def change_staff(state, actor_id, class_id, params) do
    classroom = classroom(state, class_id)
    target = params["teacher"]
    outgoing = params["replace"] || ""

    cond do
      is_nil(classroom) ->
        {:error, gettext("Classroom not found")}

      not Enum.any?(candidates(state, classroom, actor_id), &(&1.id == target)) ->
        {:error, gettext("Choose another teacher from the institution.")}

      outgoing != "" and outgoing not in classroom.teachers ->
        {:error, gettext("Choose a teacher currently assigned to this classroom.")}

      true ->
        apply_staff(state, actor_id, classroom, target, outgoing)
    end
  end

  defp apply_staff(state, actor_id, classroom, target, outgoing) do
    teachers = Enum.reject(classroom.teachers, &(&1 == outgoing)) ++ [target]

    classes =
      Enum.map(
        state.classrooms,
        &if(&1.id == classroom.id, do: %{&1 | teachers: teachers}, else: &1)
      )

    action =
      if outgoing == "",
        do: gettext("Teacher added to classroom"),
        else: gettext("Classroom teacher replaced")

    target_label = teacher(state, target).name <> " · " <> classroom.code

    target_label =
      if outgoing == "",
        do: target_label,
        else: teacher(state, outgoing).name <> " → " <> target_label

    {:ok, log(%{state | classrooms: classes}, actor_id, action, target_label)}
  end

  def change_role(state, actor_id, id, role) when role in ~w(teacher admin) do
    member = teacher(state, id)

    cond do
      is_nil(member) ->
        {:error, gettext("Teacher not found.")}

      member.admin? and role == "teacher" and Enum.count(state.teachers, & &1.admin?) == 1 ->
        {:error, gettext("Keep at least one institution administrator.")}

      true ->
        teachers =
          Enum.map(
            state.teachers,
            &if(&1.id == id, do: %{&1 | admin?: role == "admin"}, else: &1)
          )

        action =
          if role == "admin",
            do: gettext("Institution administrator appointed"),
            else: gettext("Institution administrator role removed")

        {:ok, log(%{state | teachers: teachers}, actor_id, action, member.name)}
    end
  end

  def change_role(_state, _actor_id, _id, _role), do: {:error, gettext("Choose a valid role.")}

  def remove_teacher(state, actor_id, id) do
    member = teacher(state, id)

    cond do
      is_nil(member) ->
        {:error, gettext("Teacher not found.")}

      id == actor_id ->
        {:error, gettext("You cannot remove your own account.")}

      class_count(state, id) > 0 ->
        {:error, gettext("Reassign this teacher’s classrooms before removing them.")}

      member.admin? and Enum.count(state.teachers, & &1.admin?) == 1 ->
        {:error, gettext("Keep at least one institution administrator.")}

      true ->
        {:ok,
         log(
           %{state | teachers: Enum.reject(state.teachers, &(&1.id == id))},
           actor_id,
           gettext("Teacher removed from institution"),
           member.name
         )}
    end
  end

  def rename(state, actor_id, name) do
    name = String.trim(name)

    if name == "" or String.length(name) > 100 do
      {:error, gettext("Enter an institution name of 1 to 100 characters.")}
    else
      {:ok, log(%{state | name: name}, actor_id, gettext("Institution renamed"), name)}
    end
  end

  defp log(state, actor_id, action, target) do
    event = %{
      actor: teacher(state, actor_id).name,
      action: action,
      target: target,
      time: GradePushWeb.Presentation.datetime(DateTime.utc_now())
    }

    %{state | history: [event | state.history]}
  end
end
