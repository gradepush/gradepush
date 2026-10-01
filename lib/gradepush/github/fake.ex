defmodule GradePush.GitHub.Fake do
  @moduledoc """
  Deterministic GitHub adapter for demos and tests. It never sends network requests.
  """

  @behaviour GradePush.GitHub

  alias GradePush.GitHub.Actions
  alias GradePush.GitHub.Fake.Store

  @installation %{
    "id" => 123,
    "app_id" => 456,
    "account" => %{"id" => 789, "login" => "gradepush-test", "type" => "Organization"},
    "repository_selection" => "all",
    "permissions" => %{"administration" => "write"}
  }

  @membership_key {__MODULE__, :organization_memberships}
  @test_state_key {__MODULE__, :test_state}
  @workflow_sha "test-workflow-file-sha"

  def reset! do
    Store.reset()
    Process.delete(@membership_key)
    Process.delete(@test_state_key)
    :ok
  end

  def set_organization_membership(organization, membership)
      when is_binary(organization) and is_map(membership) do
    memberships = Process.get(@membership_key, %{})
    Process.put(@membership_key, Map.put(memberships, String.downcase(organization), membership))
    :ok
  end

  def set_organization_membership(access_token, organization, membership) do
    memberships = Process.get(@membership_key, %{})
    key = {access_token, String.downcase(organization)}
    Process.put(@membership_key, Map.put(memberships, key, membership))
    :ok
  end

  def fail_next(operation, reason) when is_atom(operation) do
    state = Process.get(@test_state_key, %{})
    faults = Map.put(Map.get(state, :faults, %{}), operation, reason)
    Process.put(@test_state_key, Map.put(state, :faults, faults))
    :ok
  end

  def set_installations(installations) when is_list(installations) do
    state = Process.get(@test_state_key, %{})
    Process.put(@test_state_key, Map.put(state, :installations, installations))
    :ok
  end

  def set_workflow_file_sha(owner, repository, sha) when is_binary(sha) do
    state = Process.get(@test_state_key, %{})
    shas = Map.put(Map.get(state, :workflow_file_shas, %{}), {owner, repository}, sha)
    Process.put(@test_state_key, Map.put(state, :workflow_file_shas, shas))
    :ok
  end

  def set_workflow_run(owner, repository, run_id, attempt, attrs) do
    state = Process.get(@test_state_key, %{})
    runs = Map.put(Map.get(state, :runs, %{}), {owner, repository, run_id, attempt}, attrs)
    Process.put(@test_state_key, Map.put(state, :runs, runs))
    :ok
  end

  def set_workflow_jobs(owner, repository, run_id, attempt, jobs) do
    state = Process.get(@test_state_key, %{})
    results = Map.put(Map.get(state, :jobs, %{}), {owner, repository, run_id, attempt}, jobs)
    Process.put(@test_state_key, Map.put(state, :jobs, results))
    :ok
  end

  def collaborators(owner, repository) do
    Store.get({:collaborators, owner, repository}, [])
  end

  @impl true
  def convert_manifest(_code) do
    {:ok,
     %{
       "id" => 456,
       "client_id" => "test-client-id",
       "client_secret" => "test-client-secret",
       "pem" => "test-private-key",
       "webhook_secret" => "test-webhook-secret",
       "slug" => "gradepush-test",
       "html_url" => "https://github.com/apps/gradepush-test"
     }}
  end

  @impl true
  def exchange_user_code(_code, _client_id, _client_secret) do
    {:ok, %{"access_token" => "test-user-token", "refresh_token" => "test-refresh-token"}}
  end

  @impl true
  def get_user(_access_token), do: {:ok, %{"id" => 234, "login" => "teacher-test"}}

  @impl true
  def refresh_user_token(_refresh_token, _client_id, _client_secret) do
    {:ok,
     %{"access_token" => "test-refreshed-user-token", "refresh_token" => "test-refresh-token"}}
  end

  @impl true
  def installation_token(_credentials, installation_id, _options \\ []) do
    if installation_id == 123,
      do: {:ok, %{"token" => "test-installation-token", "expires_at" => "2099-01-01T00:00:00Z"}},
      else: {:error, :not_found}
  end

  @impl true
  def list_installations(_credentials), do: {:ok, installations()}

  @impl true
  def get_installation(_credentials, installation_id), do: find_installation(installation_id)

  @impl true
  def list_user_installations(_access_token), do: {:ok, installations()}

  @impl true
  def get_user_installation(_access_token, installation_id),
    do: find_installation(installation_id)

  defp installations do
    installation =
      if Application.get_env(:gradepush, :demo_mode, false) do
        Map.put(@installation, "account", %{
          "id" => 9_000_000_789,
          "login" => "gradepush-demo",
          "type" => "Organization"
        })
      else
        @installation
      end

    Map.get(Process.get(@test_state_key, %{}), :installations, [installation])
  end

  defp find_installation(id) do
    case Enum.find(installations(), &(&1["id"] == id)) do
      nil -> {:error, :not_found}
      installation -> {:ok, installation}
    end
  end

  @impl true
  def get_user_organization_membership(access_token, organization) do
    memberships = Process.get(@membership_key, %{})

    membership =
      Map.get(memberships, {access_token, String.downcase(organization)}) ||
        Map.get(memberships, String.downcase(organization), default_membership(organization))

    case take_fault(:get_user_organization_membership) do
      nil -> {:ok, membership}
      error -> error
    end
  end

  @impl true
  def get_user_by_id(_access_token, account_id) when is_integer(account_id) and account_id > 0 do
    {:ok, %{"id" => account_id, "login" => "student-#{account_id}"}}
  end

  def get_user_by_id(_access_token, _account_id), do: {:error, :invalid_github_id}

  @impl true
  def list_user_installation_repositories(access_token, installation_id, options \\ [])

  def list_user_installation_repositories(_access_token, 123, _options) do
    {:ok, [template_repository("gradepush-test", "starter", true)]}
  end

  def list_user_installation_repositories(_access_token, _installation_id, _options),
    do: {:error, :not_found}

  @impl true
  def list_template_repositories(_access_token, organization) do
    {:ok, [template_repository(organization, "starter", true)]}
  end

  @impl true
  def get_repository(_access_token, owner, repository) do
    case Store.get({:repository, owner, repository}) do
      nil -> {:error, {:http_error, 404}}
      value -> {:ok, value}
    end
  end

  @impl true
  def create_repository(_access_token, organization, attributes) do
    name = field(attributes, :repository_name)
    template_owner = field(attributes, :template_owner)
    template_name = field(attributes, :template_name)

    with true <- is_binary(organization) and organization != "",
         true <- is_binary(name) and name != "",
         true <- is_nil(template_owner) == is_nil(template_name) do
      private = field(attributes, :visibility) != "public"

      repository = %{
        "id" => repository_id(organization, name),
        "name" => name,
        "full_name" => "#{organization}/#{name}",
        "description" => field(attributes, :description),
        "private" => private,
        "html_url" => "https://github.com/#{organization}/#{name}",
        "owner" => %{"id" => 789, "login" => organization}
      }

      case Store.put_new({:repository, organization, name}, repository) do
        :ok -> {:ok, repository}
        :error -> {:error, :repository_name_taken}
      end
    else
      false -> {:error, :invalid_repository}
    end
  end

  @impl true
  def add_collaborator(_access_token, owner, repository, username, permission)
      when permission in ["pull", "push"] do
    with nil <- take_fault(:add_collaborator),
         {:ok, _repository} <- get_repository("test-installation-token", owner, repository),
         true <- is_binary(username) and byte_size(username) in 1..39 do
      key = {:collaborators, owner, repository}

      Store.update(key, fn members ->
        Enum.uniq([username | members || []])
      end)

      {:ok, nil}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_github_login}
    end
  end

  def add_collaborator(_access_token, _owner, _repository, _username, _permission),
    do: {:error, :invalid_permission}

  @impl true
  def remove_collaborator(_token, owner, repository, username) do
    with nil <- take_fault(:remove_collaborator),
         {:ok, _} <- get_repository("test-installation-token", owner, repository) do
      Store.update({:collaborators, owner, repository}, &List.delete(&1 || [], username))
      {:ok, nil}
    end
  end

  @impl true
  def list_repository_invitations(_token, owner, repository) do
    with nil <- take_fault(:list_repository_invitations) do
      {:ok, Store.get({:repository_invitations, owner, repository}, [])}
    end
  end

  @impl true
  def delete_repository_invitation(_token, owner, repository, invitation_id) do
    with nil <- take_fault(:delete_repository_invitation) do
      Store.update({:repository_invitations, owner, repository}, fn invitations ->
        Enum.reject(invitations || [], &(&1["id"] == invitation_id))
      end)

      {:ok, nil}
    end
  end

  @impl true
  def list_commits(_access_token, _owner, _repository, _options \\ []), do: {:ok, []}

  @impl true
  def get_workflow_run(_access_token, owner, repository, run_id, attempt) do
    with {:ok, _repository} <- get_repository("test-installation-token", owner, repository),
         tests when is_list(tests) <-
           Store.get({:workflow, owner, repository}) do
      {:ok,
       Map.merge(
         %{
           "id" => run_id,
           "run_attempt" => attempt,
           "workflow_id" => 1122,
           "path" => ".github/workflows/gradepush.yml@refs/heads/main",
           "event" => "push",
           "status" => "completed",
           "conclusion" => "success",
           "head_sha" => String.duplicate("a", 40),
           "html_url" => "https://github.com/#{owner}/#{repository}/actions/runs/#{run_id}"
         },
         workflow_run_attrs(owner, repository, run_id, attempt)
       )}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def get_repository_file(_access_token, owner, repository, path, _ref) do
    case Store.get({:workflow, owner, repository}) do
      tests when is_list(tests) and path == ".github/workflows/gradepush.yml" ->
        state = Process.get(@test_state_key, %{})

        sha =
          Map.get(Map.get(state, :workflow_file_shas, %{}), {owner, repository}, @workflow_sha)

        {:ok, %{"sha" => sha}}

      _ ->
        {:error, {:http_error, 404}}
    end
  end

  @impl true
  def list_workflow_jobs(_access_token, owner, repository, run_id, attempt) do
    case Process.get(@test_state_key, %{})
         |> Map.get(:jobs, %{})
         |> Map.fetch({owner, repository, run_id, attempt}) do
      {:ok, jobs} -> {:ok, jobs}
      :error -> default_workflow_jobs(owner, repository, run_id, attempt)
    end
  end

  defp default_workflow_jobs(owner, repository, run_id, attempt) do
    case Store.get({:workflow, owner, repository}) do
      tests when is_list(tests) ->
        {:ok,
         Enum.map(tests, fn test ->
           %{
             "name" => "GradePush test [gp-test-#{field(test, :id)}] #{field(test, :name)}",
             "conclusion" =>
               Map.get(
                 workflow_run_attrs(owner, repository, run_id, attempt),
                 "conclusion",
                 "success"
               )
           }
         end)}

      nil ->
        {:error, :not_found}
    end
  end

  defp workflow_run_attrs(owner, repository, run_id, attempt) do
    Process.get(@test_state_key, %{})
    |> Map.get(:runs, %{})
    |> Map.get({owner, repository, run_id, attempt}, %{})
  end

  @impl true
  def install_autograding_workflow(_access_token, owner, repository, tests) do
    case take_fault(:install_autograding_workflow) do
      {:error, reason} ->
        {:error, reason}

      nil ->
        with {:ok, _repository} <- get_repository("test-installation-token", owner, repository),
             {:ok, _workflow} <- Actions.generate_workflow(tests) do
          Store.put({:workflow, owner, repository}, tests)

          {:ok,
           %{
             workflow_id: 1122,
             workflow_path: ".github/workflows/gradepush.yml",
             workflow_file_sha: @workflow_sha,
             workflow_commit_sha: String.duplicate("b", 40)
           }}
        else
          {:error, _reason} = error -> error
        end
    end
  end

  @impl true
  def put_repository_file(_access_token, owner, repository, _path, _content, _attributes) do
    case get_repository("test-installation-token", owner, repository) do
      {:ok, _repository} -> {:ok, %{"content" => %{"sha" => @workflow_sha}}}
      error -> error
    end
  end

  defp template_repository(organization, name, private) do
    %{
      id: repository_id(organization, name),
      name: name,
      full_name: "#{organization}/#{name}",
      description: "GradePush demo starter template",
      private: private,
      html_url: "https://github.com/#{organization}/#{name}",
      default_branch: "main"
    }
  end

  defp repository_id(owner, name) do
    <<id::unsigned-64, _::binary>> = :crypto.hash(:sha256, "#{owner}/#{name}")
    rem(id, 9_223_372_036_854_775_806) + 1
  end

  defp take_fault(operation) do
    state = Process.get(@test_state_key, %{})
    faults = Map.get(state, :faults, %{})

    case Map.pop(faults, operation) do
      {nil, _faults} ->
        nil

      {reason, remaining} ->
        Process.put(@test_state_key, Map.put(state, :faults, remaining))
        {:error, reason}
    end
  end

  defp default_membership("gradepush-test"), do: %{"state" => "active", "role" => "admin"}
  defp default_membership("gradepush-demo"), do: %{"state" => "active", "role" => "admin"}
  defp default_membership(_organization), do: %{"state" => "active", "role" => "member"}

  defp field(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
