defmodule GradePush.GitHub do
  @moduledoc """
  Boundary for GitHub authentication, repository operations, and webhook validation.
  """

  @callback convert_manifest(String.t()) :: {:ok, map()} | {:error, term()}
  @callback exchange_user_code(String.t(), String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback get_user(String.t()) :: {:ok, map()} | {:error, term()}
  @callback refresh_user_token(String.t(), String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback installation_token(map(), pos_integer(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback list_installations(map()) :: {:ok, [map()]} | {:error, term()}
  @callback get_installation(map(), pos_integer()) :: {:ok, map()} | {:error, term()}
  @callback list_user_installations(String.t()) :: {:ok, [map()]} | {:error, term()}
  @callback get_user_installation(String.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  @callback get_user_organization_membership(String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback get_user_by_id(String.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  @callback list_user_installation_repositories(String.t(), pos_integer(), keyword()) ::
              {:ok, [map()]} | {:error, term()}
  @callback list_template_repositories(String.t(), String.t()) ::
              {:ok, [map()]} | {:error, term()}
  @callback get_repository(String.t(), String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback create_repository(String.t(), String.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback add_collaborator(String.t(), String.t(), String.t(), String.t(), String.t()) ::
              {:ok, map() | nil} | {:error, term()}
  @callback list_commits(String.t(), String.t(), String.t(), keyword()) ::
              {:ok, [map()]} | {:error, term()}
  @callback get_workflow_run(String.t(), String.t(), String.t(), pos_integer(), pos_integer()) ::
              {:ok, map()} | {:error, term()}
  @callback get_repository_file(String.t(), String.t(), String.t(), String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback list_workflow_jobs(String.t(), String.t(), String.t(), pos_integer(), pos_integer()) ::
              {:ok, [map()]} | {:error, term()}
  @callback install_autograding_workflow(String.t(), String.t(), String.t(), [map()]) ::
              {:ok, map()} | {:error, term()}
  @callback put_repository_file(String.t(), String.t(), String.t(), String.t(), String.t(), map()) ::
              {:ok, map()} | {:error, term()}

  def adapter do
    if Application.get_env(:gradepush, :demo_mode, false) do
      GradePush.GitHub.Fake
    else
      Application.get_env(:gradepush, __MODULE__, [])
      |> Keyword.get(:adapter, GradePush.GitHub.Real)
    end
  end

  def convert_manifest(code), do: call(:convert_manifest, [code])

  def exchange_user_code(code, client_id, client_secret),
    do: call(:exchange_user_code, [code, client_id, client_secret])

  def get_user(access_token), do: call(:get_user, [access_token])

  def refresh_user_token(refresh_token, client_id, client_secret),
    do: call(:refresh_user_token, [refresh_token, client_id, client_secret])

  def installation_token(credentials, installation_id, options \\ []),
    do: call(:installation_token, [credentials, installation_id, options])

  def list_installations(credentials), do: call(:list_installations, [credentials])

  def get_installation(credentials, installation_id),
    do: call(:get_installation, [credentials, installation_id])

  def list_user_installations(access_token), do: call(:list_user_installations, [access_token])

  def get_user_installation(access_token, installation_id),
    do: call(:get_user_installation, [access_token, installation_id])

  def get_user_organization_membership(access_token, organization),
    do: call(:get_user_organization_membership, [access_token, organization])

  def get_user_by_id(access_token, account_id),
    do: call(:get_user_by_id, [access_token, account_id])

  def list_user_installation_repositories(access_token, installation_id, options \\ []),
    do: call(:list_user_installation_repositories, [access_token, installation_id, options])

  def list_template_repositories(access_token, organization),
    do: call(:list_template_repositories, [access_token, organization])

  def get_repository(access_token, owner, repository),
    do: call(:get_repository, [access_token, owner, repository])

  def create_repository(access_token, organization, attributes),
    do: call(:create_repository, [access_token, organization, attributes])

  def add_collaborator(access_token, owner, repository, username, permission),
    do: call(:add_collaborator, [access_token, owner, repository, username, permission])

  def list_commits(access_token, owner, repository, options \\ []),
    do: call(:list_commits, [access_token, owner, repository, options])

  def get_workflow_run(access_token, owner, repository, run_id, attempt),
    do: call(:get_workflow_run, [access_token, owner, repository, run_id, attempt])

  def get_repository_file(access_token, owner, repository, path, ref),
    do: call(:get_repository_file, [access_token, owner, repository, path, ref])

  def list_workflow_jobs(access_token, owner, repository, run_id, attempt),
    do: call(:list_workflow_jobs, [access_token, owner, repository, run_id, attempt])

  def install_autograding_workflow(access_token, owner, repository, tests),
    do: call(:install_autograding_workflow, [access_token, owner, repository, tests])

  def put_repository_file(access_token, owner, repository, path, content, attributes),
    do: call(:put_repository_file, [access_token, owner, repository, path, content, attributes])

  defp call(function, arguments), do: apply(adapter(), function, arguments)
end
