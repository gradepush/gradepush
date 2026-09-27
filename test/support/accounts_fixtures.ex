defmodule GradePush.AccountsFixtures do
  @moduledoc false

  alias GradePush.Accounts
  alias GradePush.Accounts.{Institution, InstitutionMembership, PlatformOperator, User}
  alias GradePush.Crypto
  alias GradePush.Installation
  alias GradePush.Installation.BootstrapCredential
  alias GradePush.Repo

  def user_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    github_id = Map.get(attrs, :github_id, System.unique_integer([:positive, :monotonic]))

    {:ok, user} =
      Accounts.upsert_github_user(
        Map.merge(
          %{github_id: github_id, login: "student-#{github_id}", name: "Test User"},
          attrs
        )
      )

    user
  end

  def bootstrap_fixture(attrs \\ %{}) do
    user =
      user_fixture(
        Map.merge(%{login: "admin-#{System.unique_integer([:positive])}"}, Map.new(attrs))
      )

    institution =
      %Institution{}
      |> Institution.changeset(%{name: "Test Institution"})
      |> Repo.insert!()

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    membership_fixture!(institution, user, :admin, now)
    membership_fixture!(institution, user, :teacher, now)

    %PlatformOperator{user_id: user.id, added_by_id: user.id}
    |> Repo.insert!()

    %{user: user, institution: institution}
  end

  def configured_gradepush_fixture do
    ExUnit.CaptureLog.capture_log(fn ->
      {:ok, :created} = Installation.initialize_bootstrap()
    end)

    credential = Repo.get!(BootstrapCredential, 1)
    {:ok, token} = Crypto.decrypt(credential.token_encrypted, "bootstrap.token")
    nonce = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    {:ok, %{state: state}} =
      Installation.begin_setup(token, "Test Institution", "https://gradepush.example", nonce)

    {:ok, %{state: state}} = Installation.convert_manifest(state, "manifest-code", nonce)

    {:ok, %{user: user, institution: institution, session_token: session_token}} =
      Installation.finish_setup(state, "oauth-code", nonce)

    %{user: user, institution: institution, session_token: session_token}
  end

  def teacher_membership_fixture(%User{} = user) do
    institution = Accounts.institution() || create_institution!()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    case Repo.get_by(InstitutionMembership,
           institution_id: institution.id,
           user_id: user.id,
           role: :teacher
         ) do
      %InstitutionMembership{} = membership -> membership
      nil -> membership_fixture!(institution, user, :teacher, now)
    end
  end

  def student_membership_fixture(%User{} = user, attrs \\ %{}) do
    attrs = Map.new(attrs)

    {:ok, membership} =
      Accounts.enroll_student(user, %{
        name: Map.get(attrs, :name, "Test Student"),
        student_id: Map.get(attrs, :student_id, "student-#{user.github_id}")
      })

    membership
  end

  defp create_institution! do
    %Institution{}
    |> Institution.changeset(%{name: "Test Institution"})
    |> Repo.insert!()
  end

  defp membership_fixture!(institution, user, role, joined_at) do
    %InstitutionMembership{}
    |> InstitutionMembership.changeset(%{
      institution_id: institution.id,
      user_id: user.id,
      role: role,
      joined_at: joined_at
    })
    |> Repo.insert!()
  end
end
