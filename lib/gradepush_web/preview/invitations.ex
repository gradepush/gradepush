defmodule GradePushWeb.Preview.Invitations do
  @moduledoc "Fictional invitation states, available only through the configured UI preview."

  alias GradePush.Accounts.User
  alias GradePush.Assignments.{Assignment, Subject, Team, TeamMember}

  def lookup("assignment", "preview-" <> variant, params)
      when variant in ~w(individual team assigned waiting signed-out full) do
    team? = variant in ~w(team assigned waiting full)

    %{
      participant:
        if(variant == "signed-out" or params["signed_out"] == "true",
          do: nil,
          else: participant()
        ),
      invitation: %{
        assignment: %Assignment{
          id: 1,
          slug: "preview-#{if variant == "signed-out", do: "individual", else: variant}",
          title: if(team?, do: "Un jeu, une équipe", else: "Premiers pas en Python"),
          instructions:
            "## À vous de jouer\n\nCréez un petit jeu de devinettes en Python. Utilisez des variables, des conditions et une boucle pour guider le joueur.\n\n1. Consultez le fichier README de votre dépôt.\n2. Complétez les exercices.\n3. Poussez votre code sur GitHub.\n\nLes tests automatiques vous aideront à vérifier votre progression.",
          kind: if(team?, do: "team", else: "individual"),
          team_mode: if(variant in ~w(assigned waiting), do: "teacher", else: "students"),
          team_size: 3,
          deadline_at: ~U[2026-10-19 03:59:00.000000Z]
        },
        classroom: %{
          id: 1,
          slug: "preview-programming",
          title: "Introduction à la programmation",
          code: "420-1P1-SO",
          semester: :fall,
          academic_year: "2026"
        },
        current_team: if(variant == "assigned", do: %{id: 1, name: "Les Bâtisseurs"}),
        team_options: [
          %{id: 1, name: "Les Bâtisseurs", member_count: 2, team_size: 3},
          %{id: 2, name: "Les Explorateurs", member_count: 1, team_size: 3}
        ]
      }
    }
  end

  def lookup(_kind, _token, _params), do: nil

  def participant, do: %User{id: 1, name: "Camille Roy", login: "camille-roy", avatar_url: nil}

  def accept(%{assignment: %{team_mode: "teacher"}, current_team: nil}, _attrs),
    do: {:error, :team_assignment_required}

  def accept(%{assignment: %{slug: "preview-full"}}, %{"team_id" => "1"}),
    do: {:error, :team_full}

  def accept(%{assignment: %{kind: "individual"}}, _attrs), do: {:ok, %{}}
  def accept(%{current_team: %{name: name}}, _attrs), do: {:ok, %{team: name}}

  def accept(invitation, attrs) do
    selected = Enum.find(invitation.team_options, &(to_string(&1.id) == attrs["team_id"]))
    name = if selected, do: selected.name, else: String.trim(Map.get(attrs, "team_name", ""))

    if name == "", do: {:error, :team_required}, else: {:ok, %{team: String.slice(name, 0, 120)}}
  end

  def student_assignment(%{"slug" => "preview-programming", "assignment" => token} = params) do
    case lookup("assignment", token, %{}) do
      %{invitation: invitation} -> student_details(invitation, params)
      _ -> nil
    end
  end

  def student_assignment(_params), do: nil

  defp student_details(invitation, params) do
    team =
      if invitation.assignment.kind == "team" do
        name = Map.get(params, "team", "Les Bâtisseurs") |> String.slice(0, 120)
        %Team{name: name, members: [%TeamMember{user: participant(), left_at: nil}]}
      end

    %{
      classroom: Map.merge(invitation.classroom, %{description: "", teachers: []}),
      assignment: %{invitation.assignment | tests: []},
      subject: %Subject{kind: invitation.assignment.kind, team: team, user: participant()},
      repository: nil,
      latest_push: nil
    }
  end
end
