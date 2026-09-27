defmodule GradePush.Installation do
  @moduledoc """
  Manages first-run setup, GitHub App credentials, and teacher GitHub authorization.
  """

  import Ecto.Query
  require Logger

  alias GradePush.Accounts
  alias GradePush.Accounts.{Institution, InstitutionMembership, PlatformOperator, User}
  alias GradePush.Crypto
  alias GradePush.Installation.{BootstrapCredential, GitHubApp, GitHubUserCredentials}
  alias GradePush.Repo

  @bootstrap_id 1
  @setup_state_seconds 30 * 60
  @credential_purposes %{
    client_secret: "github_app.client_secret",
    private_key: "github_app.private_key",
    webhook_secret: "github_app.webhook_secret"
  }

  def configured?, do: not is_nil(Accounts.institution())

  @doc "Returns a private setup link for use by the server operator."
  def setup_link(base_url) when is_binary(base_url) do
    with false <- configured?(),
         true <- valid_base_url?(base_url),
         %BootstrapCredential{} = credential <- Repo.get(BootstrapCredential, @bootstrap_id),
         {:ok, token} <- Crypto.decrypt(credential.token_encrypted, "bootstrap.token") do
      {:ok,
       String.trim_trailing(base_url, "/") <> "/setup#setup_token=" <> URI.encode_www_form(token)}
    else
      _ -> {:error, :setup_not_available}
    end
  end

  def initialize_bootstrap do
    case Repo.transaction(fn -> bootstrap_token_record() end) do
      {:ok, {:configured, _}} ->
        {:ok, :configured}

      {:ok, {:ready, token, status}} ->
        Logger.warning("GradePush one-time setup token: #{token}")
        {:ok, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def begin_setup(token, institution_name, base_url, browser_nonce)
      when is_binary(token) and is_binary(institution_name) and is_binary(base_url) and
             is_binary(browser_nonce) do
    with :ok <- validate_setup_inputs(token, institution_name, base_url, browser_nonce) do
      start_setup(token, String.trim(institution_name), base_url, browser_nonce)
    end
  end

  def begin_setup(_token, _name, _base_url, _browser_nonce), do: {:error, :invalid_setup_token}

  defp validate_setup_inputs(token, institution_name, base_url, browser_nonce) do
    cond do
      byte_size(token) > 128 ->
        {:error, :invalid_setup_token}

      not valid_browser_nonce?(browser_nonce) ->
        {:error, :invalid_setup_state}

      String.trim(institution_name) == "" or String.length(String.trim(institution_name)) > 100 ->
        {:error, :invalid_institution_name}

      not valid_base_url?(base_url) ->
        {:error, :invalid_base_url}

      true ->
        :ok
    end
  end

  defp start_setup(token, institution_name, base_url, browser_nonce) do
    state = random_token()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    browser_hash = Crypto.hash(browser_nonce)

    Repo.transaction(fn ->
      credential = lock_bootstrap_credential()

      begin_setup_for_credential(
        credential,
        token,
        institution_name,
        base_url,
        state,
        browser_hash,
        now
      )
    end)
  end

  defp begin_setup_for_credential(
         credential,
         token,
         institution_name,
         base_url,
         state,
         browser_hash,
         now
       ) do
    reason = setup_start_error(credential, token, browser_hash, now)

    if reason do
      Repo.rollback(reason)
    else
      credential
      |> Ecto.Changeset.change(%{
        state_hash: Crypto.hash(state),
        setup_browser_hash: browser_hash,
        state_expires_at: DateTime.add(now, @setup_state_seconds, :second),
        institution_name: institution_name,
        pending_app_encrypted: nil,
        step: "manifest"
      })
      |> Repo.update!()

      %{
        state: state,
        action: manifest_action(state, base_url),
        manifest: manifest_payload(base_url)
      }
    end
  end

  defp setup_start_error(nil, _token, _browser_hash, _now), do: :setup_not_available

  defp setup_start_error(credential, token, browser_hash, now) do
    cond do
      configured?() -> :already_configured
      not Crypto.secure_compare(credential.token_hash, Crypto.hash(token)) -> :invalid_setup_token
      not setup_available_for_browser?(credential, browser_hash, now) -> :setup_in_progress
      true -> nil
    end
  end

  def convert_manifest(state, code, browser_nonce)
      when is_binary(state) and byte_size(state) in 32..128 and is_binary(code) and
             byte_size(code) in 1..2_048 and is_binary(browser_nonce) do
    with {:ok, _credential} <- setup_state(state, "manifest", browser_nonce),
         {:ok, manifest} <- GradePush.GitHub.convert_manifest(code),
         {:ok, normalized} <- normalize_manifest(manifest),
         {:ok, encrypted} <- encrypt_pending_app(normalized) do
      next_state = random_token()
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      persist_manifest_conversion(
        state,
        browser_nonce,
        normalized.client_id,
        encrypted,
        next_state,
        now
      )
    end
  end

  def convert_manifest(_state, _code, _browser_nonce), do: {:error, :invalid_setup_state}

  defp persist_manifest_conversion(state, browser_nonce, client_id, encrypted, next_state, now) do
    Repo.transaction(fn ->
      credential = lock_bootstrap_credential()
      ensure_setup_state!(credential, state, "manifest", browser_nonce, now)

      credential
      |> Ecto.Changeset.change(%{
        state_hash: Crypto.hash(next_state),
        state_expires_at: DateTime.add(now, @setup_state_seconds, :second),
        pending_app_encrypted: encrypted,
        step: "oauth"
      })
      |> Repo.update!()

      %{state: next_state, client_id: client_id}
    end)
  end

  defp ensure_setup_state!(credential, state, step, browser_nonce, now) do
    unless valid_state?(credential, state, step, browser_nonce, now),
      do: Repo.rollback(:invalid_setup_state)
  end

  def setup_authorization_url(state, callback_url, browser_nonce)
      when is_binary(state) and byte_size(state) in 32..128 and is_binary(callback_url) and
             is_binary(browser_nonce) do
    with {:ok, %{app: app}} <- pending_setup(state, browser_nonce) do
      {:ok, authorization_url(app["client_id"], state, callback_url)}
    end
  end

  def setup_authorization_url(_state, _callback_url, _browser_nonce),
    do: {:error, :invalid_setup_state}

  def finish_setup(state, code, browser_nonce)
      when is_binary(state) and byte_size(state) in 32..128 and is_binary(code) and
             byte_size(code) in 1..2_048 and is_binary(browser_nonce) do
    with {:ok, %{credential: bootstrap, app: app}} <- pending_setup(state, browser_nonce),
         {:ok, token_response} <-
           GradePush.GitHub.exchange_user_code(code, app["client_id"], app["client_secret"]),
         access_token when is_binary(access_token) <- field(token_response, :access_token),
         {:ok, github_user} <- GradePush.GitHub.get_user(access_token),
         {:ok, user_attrs} <- normalize_github_user(github_user),
         {:ok, result} <-
           persist_setup(state, bootstrap, app, user_attrs, token_response, browser_nonce) do
      {:ok, result}
    else
      nil -> {:error, :invalid_github_response}
      {:error, _reason} = error -> error
      {:ok, _other} -> {:error, :invalid_github_response}
      _other -> {:error, :invalid_github_response}
    end
  end

  def finish_setup(_state, _code, _browser_nonce), do: {:error, :invalid_setup_state}

  def github_app_metadata do
    case Repo.get_by(GitHubApp, singleton_key: true) do
      nil ->
        nil

      app ->
        %{app_id: app.app_id, client_id: app.client_id, slug: app.slug, html_url: app.html_url}
    end
  end

  def github_app_credentials do
    case Repo.get_by(GitHubApp, singleton_key: true) do
      nil ->
        {:error, :not_configured}

      app ->
        with {:ok, client_secret} <-
               Crypto.decrypt(app.client_secret_encrypted, @credential_purposes.client_secret),
             {:ok, private_key} <-
               Crypto.decrypt(app.private_key_encrypted, @credential_purposes.private_key),
             {:ok, webhook_secret} <-
               Crypto.decrypt(app.webhook_secret_encrypted, @credential_purposes.webhook_secret) do
          {:ok,
           %{
             app_id: app.app_id,
             client_id: app.client_id,
             client_secret: client_secret,
             private_key: private_key,
             webhook_secret: webhook_secret
           }}
        else
          _other -> {:error, :credential_decryption_failed}
        end
    end
  end

  def list_user_organizations(%User{} = actor) do
    with true <- Accounts.teacher?(actor),
         {:ok, access_token} <- user_access_token(actor),
         {:ok, installations} <- GradePush.GitHub.list_user_installations(access_token) do
      organizations =
        installations
        |> Enum.filter(&(integer_field(&1, :app_id) == configured_app_id()))
        |> Enum.map(fn installation ->
          account = field(installation, :account) || %{}

          %{
            installation_id: field(installation, :id),
            github_id: field(account, :id),
            login: field(account, :login),
            avatar_url: field(account, :avatar_url),
            permissions: field(installation, :permissions) || %{}
          }
        end)
        |> Enum.filter(&(is_integer(&1.installation_id) and is_binary(&1.login)))

      {:ok, organizations}
    else
      false -> {:error, :unauthorized}
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_github_response}
    end
  end

  def list_template_repositories(%User{} = actor, organization) when is_binary(organization) do
    with true <- Accounts.teacher?(actor),
         {:ok, organizations} <- list_user_organizations(actor),
         true <-
           Enum.any?(organizations, &(String.downcase(&1.login) == String.downcase(organization))),
         {:ok, access_token} <- user_access_token(actor),
         {:ok, repositories} <-
           GradePush.GitHub.list_template_repositories(access_token, organization) do
      {:ok, repositories}
    else
      false -> {:error, :unauthorized}
      {:error, _reason} = error -> error
      _other -> {:error, :organization_not_authorized}
    end
  end

  def list_template_repositories(_actor, _organization), do: {:error, :invalid_organization}

  def revoke_user_authorization(github_user_id) when is_integer(github_user_id) do
    case Repo.get_by(User, github_id: github_user_id) do
      nil ->
        :ok

      user ->
        Repo.transaction(fn ->
          Repo.delete_all(
            from(credentials in GitHubUserCredentials, where: credentials.user_id == ^user.id)
          )

          :ok
        end)
        |> case do
          {:ok, :ok} -> Accounts.revoke_user_sessions(user.id)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def revoke_user_authorization(_github_user_id), do: {:error, :invalid_github_id}

  def authenticate_github_user(code) when is_binary(code) do
    with {:ok, app} <- github_app_credentials(),
         {:ok, token_response} <-
           GradePush.GitHub.exchange_user_code(code, app.client_id, app.client_secret),
         access_token when is_binary(access_token) <- field(token_response, :access_token),
         {:ok, github_user} <- GradePush.GitHub.get_user(access_token),
         {:ok, user_attrs} <- normalize_github_user(github_user),
         {:ok, result} <- persist_sign_in(user_attrs, token_response) do
      {:ok, result}
    else
      nil -> {:error, :invalid_github_response}
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_github_response}
    end
  end

  def authenticate_github_user(_code), do: {:error, :invalid_oauth_code}

  def github_authorization_url(state, callback_url)
      when is_binary(state) and is_binary(callback_url) do
    with {:ok, app} <- github_app_credentials() do
      {:ok, authorization_url(app.client_id, state, callback_url)}
    end
  end

  def verify_user_installation(%User{} = actor, installation_id)
      when is_integer(installation_id) do
    with true <- Accounts.teacher?(actor),
         {:ok, access_token} <- user_access_token(actor),
         {:ok, user_installation} <-
           GradePush.GitHub.get_user_installation(access_token, installation_id),
         {:ok, app_credentials} <- github_app_credentials(),
         {:ok, app_installation} <-
           GradePush.GitHub.get_installation(app_credentials, installation_id),
         {:ok, verified} <-
           verified_installation(user_installation, app_installation, installation_id),
         {:ok, membership} <- organization_membership(access_token, verified.account.login),
         :ok <- require_organization_owner(membership) do
      {:ok, verified}
    else
      false -> {:error, :unauthorized}
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_installation}
    end
  end

  def verify_user_installation(_actor, _installation_id), do: {:error, :invalid_installation}

  def user_installations(%User{} = actor), do: list_user_organizations(actor)
  def user_installations(_actor), do: {:error, :unauthorized}

  def web_url do
    Application.get_env(:gradepush, GradePush.GitHub, [])
    |> Keyword.get(:web_url, "https://github.com")
  end

  defp bootstrap_token_record do
    case Repo.one(from(institution in Institution, limit: 1)) do
      %Institution{} ->
        Repo.delete_all(
          from(credential in BootstrapCredential, where: credential.id == @bootstrap_id)
        )

        {:configured, nil}

      nil ->
        credential = lock_bootstrap_credential()

        case credential && Crypto.decrypt(credential.token_encrypted, "bootstrap.token") do
          {:ok, token} -> {:ready, token, :existing}
          _other -> create_bootstrap_token(credential)
        end
    end
  end

  defp create_bootstrap_token(credential) do
    token = random_token()

    case Crypto.encrypt(token, "bootstrap.token") do
      {:ok, encrypted} -> persist_bootstrap_token(token, encrypted, credential)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp persist_bootstrap_token(token, encrypted, credential) do
    attrs = %{
      id: @bootstrap_id,
      token_hash: Crypto.hash(token),
      token_encrypted: encrypted,
      state_hash: nil,
      setup_browser_hash: nil,
      state_expires_at: nil,
      institution_name: nil,
      pending_app_encrypted: nil,
      step: "setup"
    }

    result =
      if credential do
        credential
        |> Ecto.Changeset.change(Map.delete(attrs, :id))
        |> Repo.update()
      else
        %BootstrapCredential{}
        |> Ecto.Changeset.cast(attrs, Map.keys(attrs))
        |> Ecto.Changeset.validate_required([:id, :token_hash, :token_encrypted, :step])
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:id])
      end

    case result do
      {:ok, _record} ->
        stored = Repo.get!(BootstrapCredential, @bootstrap_id)
        {:ok, stored_token} = Crypto.decrypt(stored.token_encrypted, "bootstrap.token")
        {:ready, stored_token, :created}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp lock_bootstrap_credential do
    Repo.one(
      from(credential in BootstrapCredential,
        where: credential.id == @bootstrap_id,
        lock: "FOR UPDATE",
        limit: 1
      )
    )
  end

  defp setup_state(state, step, browser_nonce) do
    now = DateTime.utc_now()

    case Repo.get(BootstrapCredential, @bootstrap_id) do
      %BootstrapCredential{} = credential ->
        if valid_state?(credential, state, step, browser_nonce, now),
          do: {:ok, credential},
          else: {:error, :invalid_setup_state}

      nil ->
        {:error, :setup_not_available}
    end
  end

  defp pending_setup(state, browser_nonce) do
    case Repo.get(BootstrapCredential, @bootstrap_id) do
      %BootstrapCredential{step: "oauth", pending_app_encrypted: encrypted} = credential
      when is_binary(encrypted) ->
        decode_pending_setup(credential, encrypted, state, browser_nonce)

      _other ->
        {:error, :invalid_setup_state}
    end
  end

  defp decode_pending_setup(credential, encrypted, state, browser_nonce) do
    with true <- valid_state?(credential, state, "oauth", browser_nonce, DateTime.utc_now()),
         {:ok, json} <- Crypto.decrypt(encrypted, "bootstrap.pending_app"),
         {:ok, app} <- Jason.decode(json) do
      {:ok, %{credential: credential, app: app}}
    else
      _other -> {:error, :invalid_setup_state}
    end
  end

  defp valid_state?(%BootstrapCredential{} = credential, state, step, browser_nonce, now) do
    credential.step == step and is_binary(credential.state_hash) and
      Crypto.secure_compare(credential.state_hash, Crypto.hash(state)) and
      valid_browser_nonce?(browser_nonce) and
      Crypto.secure_compare(credential.setup_browser_hash || <<>>, Crypto.hash(browser_nonce)) and
      not is_nil(credential.state_expires_at) and
      DateTime.compare(credential.state_expires_at, now) == :gt
  end

  defp valid_state?(_credential, _state, _step, _browser_nonce, _now), do: false

  defp setup_available_for_browser?(%BootstrapCredential{step: "setup"}, _browser_hash, _now),
    do: true

  defp setup_available_for_browser?(%BootstrapCredential{} = credential, _browser_hash, now) do
    credential.step in ["manifest", "oauth"] and
      is_struct(credential.state_expires_at, DateTime) and
      DateTime.compare(credential.state_expires_at, now) != :gt
  end

  defp setup_available_for_browser?(_credential, _browser_hash, _now), do: false

  defp valid_browser_nonce?(nonce), do: byte_size(nonce) in 32..128

  defp encrypt_pending_app(app) do
    case Jason.encode(app) do
      {:ok, json} -> Crypto.encrypt(json, "bootstrap.pending_app")
      {:error, _reason} -> {:error, :invalid_github_response}
    end
  end

  defp normalize_manifest(manifest) when is_map(manifest) do
    app = %{
      app_id: integer_field(manifest, :id),
      client_id: field(manifest, :client_id),
      client_secret: field(manifest, :client_secret),
      private_key: field(manifest, :pem),
      webhook_secret: field(manifest, :webhook_secret),
      slug: field(manifest, :slug),
      html_url: field(manifest, :html_url)
    }

    if is_integer(app.app_id) and Enum.all?(Map.values(Map.drop(app, [:app_id])), &is_binary/1) and
         Enum.all?(Map.values(Map.drop(app, [:app_id])), &(String.length(&1) > 0)) do
      {:ok, app}
    else
      {:error, :invalid_github_response}
    end
  end

  defp normalize_manifest(_manifest), do: {:error, :invalid_github_response}

  defp normalize_github_user(user) when is_map(user) do
    attrs = %{
      github_id: integer_field(user, :id),
      login: field(user, :login),
      name: field(user, :name),
      avatar_url: field(user, :avatar_url)
    }

    if is_integer(attrs.github_id) and is_binary(attrs.login),
      do: {:ok, attrs},
      else: {:error, :invalid_github_response}
  end

  defp normalize_github_user(_user), do: {:error, :invalid_github_response}

  defp persist_sign_in(user_attrs, token_response) do
    Repo.transaction(fn ->
      user =
        case Accounts.upsert_github_user(user_attrs) do
          {:ok, user} -> user
          {:error, reason} -> Repo.rollback(reason)
        end

      case store_user_credentials(user, token_response) do
        {:ok, _credentials} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      case Accounts.create_session(user) do
        {:ok, session_token} -> %{user: user, session_token: session_token}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp store_user_credentials(user, token_response) do
    case store_user_credentials!(user, token_response) do
      {:ok, _credentials} = result -> result
      {:error, _reason} = error -> error
    end
  end

  defp store_user_credentials!(user, token_response) do
    access_token = field(token_response, :access_token)
    refresh_token = field(token_response, :refresh_token)
    expires_at = expiry_datetime(field(token_response, :expires_in))
    refresh_expires_at = expiry_datetime(field(token_response, :refresh_token_expires_in))
    scope = field(token_response, :scope)
    scopes = if is_binary(scope), do: String.split(scope, ",", trim: true), else: []

    cond do
      not match?(%User{}, user) ->
        {:error, :invalid_user}

      not is_binary(access_token) or access_token == "" ->
        {:error, :invalid_github_response}

      true ->
        existing = Repo.get_by(GitHubUserCredentials, user_id: user.id)

        with {:ok, access_encrypted} <-
               Crypto.encrypt(access_token, user_credential_purpose(user.id, :access)),
             {:ok, refresh_encrypted} <-
               encrypted_refresh_token(user.id, refresh_token, existing),
             attrs = %{
               user_id: user.id,
               access_token_encrypted: access_encrypted,
               refresh_token_encrypted: refresh_encrypted,
               expires_at: expires_at,
               refresh_token_expires_at:
                 if(is_binary(refresh_token) and refresh_token != "",
                   do: refresh_expires_at,
                   else: existing && existing.refresh_token_expires_at
                 ),
               scopes: scopes
             },
             {:ok, credentials} <-
               %GitHubUserCredentials{}
               |> GitHubUserCredentials.changeset(attrs)
               |> Repo.insert(
                 on_conflict:
                   {:replace,
                    [
                      :access_token_encrypted,
                      :refresh_token_encrypted,
                      :expires_at,
                      :refresh_token_expires_at,
                      :scopes,
                      :updated_at
                    ]},
                 conflict_target: [:user_id],
                 returning: true
               ) do
          {:ok, credentials}
        else
          {:error, _reason} = error -> error
        end
    end
  end

  defp encrypted_refresh_token(user_id, refresh_token, existing) do
    case refresh_token do
      token when is_binary(token) and token != "" ->
        Crypto.encrypt(token, user_credential_purpose(user_id, :refresh))

      _other when not is_nil(existing) ->
        {:ok, existing.refresh_token_encrypted}

      _other ->
        {:ok, nil}
    end
  end

  defp user_access_token(%User{id: user_id}) do
    case Repo.get_by(GitHubUserCredentials, user_id: user_id) do
      nil ->
        {:error, :github_reauthorization_required}

      credentials ->
        if expiring_soon?(credentials.expires_at) do
          refresh_access_token(credentials)
        else
          Crypto.decrypt(
            credentials.access_token_encrypted,
            user_credential_purpose(user_id, :access)
          )
        end
    end
    |> case do
      {:ok, token} when is_binary(token) -> {:ok, token}
      {:error, :encryption_key_unavailable} -> {:error, :credential_decryption_failed}
      other -> other
    end
  end

  defp refresh_access_token(credentials) do
    user_id = credentials.user_id

    with encrypted when is_binary(encrypted) <- credentials.refresh_token_encrypted,
         {:ok, refresh_token} <-
           Crypto.decrypt(encrypted, user_credential_purpose(user_id, :refresh)),
         {:ok, app} <- github_app_credentials(),
         {:ok, token_response} <-
           GradePush.GitHub.refresh_user_token(refresh_token, app.client_id, app.client_secret),
         access_token when is_binary(access_token) <- field(token_response, :access_token),
         %User{} = user <- Accounts.get_user(user_id),
         {:ok, _stored} <- store_user_credentials(user, token_response) do
      {:ok, access_token}
    else
      nil -> {:error, :github_reauthorization_required}
      {:error, _reason} = error -> error
      _other -> {:error, :github_reauthorization_required}
    end
  end

  defp manifest_action(state, base_url) do
    URI.to_string(%URI{
      URI.parse(web_url())
      | path: "/settings/apps/new",
        query: URI.encode_query(%{state: state})
    })
    |> then(fn url -> %{url: url, manifest: Jason.encode!(manifest_payload(base_url))} end)
  end

  defp manifest_payload(base_url) do
    %{
      name: "GradePush",
      url: base_url,
      redirect_url: Path.join(base_url, "/setup/github/manifest/callback"),
      callback_urls: [
        Path.join(base_url, "/setup/github/auth/callback"),
        Path.join(base_url, "/auth/github/callback")
      ],
      setup_url: Path.join(base_url, "/setup"),
      hook_attributes: %{url: Path.join(base_url, "/webhooks/github"), active: true},
      public: true,
      default_permissions: %{
        administration: "write",
        actions: "read",
        contents: "write",
        members: "read",
        metadata: "read",
        workflows: "write"
      },
      default_events: ~w(push workflow_run),
      request_oauth_on_install: false
    }
  end

  defp authorization_url(client_id, state, callback_url) do
    URI.to_string(%URI{
      URI.parse(web_url())
      | path: "/login/oauth/authorize",
        query:
          URI.encode_query(%{
            client_id: client_id,
            redirect_uri: callback_url,
            state: state,
            allow_signup: "false"
          })
    })
  end

  defp valid_base_url?(base_url) do
    case URI.parse(base_url) do
      %URI{scheme: scheme, host: host, userinfo: nil, query: nil, fragment: nil}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _other ->
        false
    end
  end

  defp verified_installation(user_installation, app_installation, requested_id) do
    user_account = field(user_installation, :account) || %{}
    app_account = field(app_installation, :account) || %{}

    with :ok <- validate_installation_ids(user_installation, app_installation, requested_id),
         {:ok, account} <- verified_organization_account(user_account, app_account),
         :ok <- validate_installation_permissions(app_installation) do
      {:ok,
       %{
         id: requested_id,
         account: account,
         permissions: field(user_installation, :permissions) || %{},
         repository_selection: field(user_installation, :repository_selection)
       }}
    else
      _other -> {:error, :installation_not_authorized}
    end
  end

  defp validate_installation_ids(user_installation, app_installation, requested_id) do
    if integer_field(user_installation, :id) == requested_id and
         integer_field(app_installation, :id) == requested_id and
         integer_field(app_installation, :app_id) == app_id(),
       do: :ok,
       else: {:error, :installation_not_authorized}
  end

  defp verified_organization_account(user_account, app_account) do
    account_id = integer_field(user_account, :id)
    login = field(user_account, :login)

    if is_integer(account_id) and integer_field(app_account, :id) == account_id and
         is_binary(login) and field(user_account, :type) == "Organization" and
         field(app_account, :type) == "Organization" do
      {:ok, %{id: account_id, login: login, type: "Organization"}}
    else
      {:error, :installation_not_authorized}
    end
  end

  defp validate_installation_permissions(app_installation) do
    if field(field(app_installation, :permissions) || %{}, :administration) == "write",
      do: :ok,
      else: {:error, :installation_not_authorized}
  end

  defp require_organization_owner(membership) do
    if field(membership, :state) == "active" and field(membership, :role) == "admin",
      do: :ok,
      else: {:error, :organization_owner_required}
  end

  defp organization_membership(access_token, organization) do
    case GradePush.GitHub.get_user_organization_membership(access_token, organization) do
      {:error, :not_found} -> {:ok, %{state: "inactive", role: "member"}}
      {:error, {:http_error, 404}} -> {:ok, %{state: "inactive", role: "member"}}
      result -> result
    end
  end

  defp app_id do
    case github_app_metadata() do
      %{app_id: app_id} -> app_id
      _other -> nil
    end
  end

  defp configured_app_id, do: app_id()

  defp store_manifest_app!(app) do
    %GitHubApp{}
    |> GitHubApp.changeset(%{
      app_id: integer_field(app, :app_id),
      client_id: field(app, :client_id),
      client_secret_encrypted:
        encrypt!(field(app, :client_secret), @credential_purposes.client_secret),
      private_key_encrypted: encrypt!(field(app, :private_key), @credential_purposes.private_key),
      webhook_secret_encrypted:
        encrypt!(field(app, :webhook_secret), @credential_purposes.webhook_secret),
      slug: field(app, :slug),
      html_url: field(app, :html_url)
    })
    |> Repo.insert!()
  end

  defp insert_setup_user!(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert!()
  end

  defp encrypt!(value, purpose) do
    case Crypto.encrypt(value, purpose) do
      {:ok, encrypted} -> encrypted
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp expiry_datetime(value) when is_integer(value) and value > 0 do
    DateTime.add(DateTime.utc_now() |> DateTime.truncate(:microsecond), value, :second)
  end

  defp expiry_datetime(_value), do: nil

  defp expiring_soon?(nil), do: false

  defp expiring_soon?(%DateTime{} = expires_at) do
    DateTime.compare(expires_at, DateTime.add(DateTime.utc_now(), 120, :second)) != :gt
  end

  defp user_credential_purpose(user_id, type), do: "github_user.#{user_id}.#{type}_token"

  defp random_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp integer_field(map, key) do
    case field(map, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {number, ""} -> number
          _ -> nil
        end

      _other ->
        nil
    end
  end

  defp persist_setup(state, _bootstrap, app, user_attrs, token_response, browser_nonce) do
    Repo.transaction(fn ->
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      bootstrap = lock_bootstrap_credential()

      if not valid_state?(bootstrap, state, "oauth", browser_nonce, now),
        do: Repo.rollback(:invalid_setup_state)

      if Repo.exists?(from(institution in Institution)), do: Repo.rollback(:already_configured)

      user = insert_setup_user!(user_attrs)

      institution =
        %Institution{}
        |> Institution.changeset(%{
          name: bootstrap.institution_name,
          time_zone: "America/Toronto"
        })
        |> Repo.insert!()

      %InstitutionMembership{}
      |> InstitutionMembership.changeset(%{
        institution_id: institution.id,
        user_id: user.id,
        role: :admin,
        joined_at: now
      })
      |> Repo.insert!()

      %InstitutionMembership{}
      |> InstitutionMembership.changeset(%{
        institution_id: institution.id,
        user_id: user.id,
        role: :teacher,
        joined_at: now
      })
      |> Repo.insert!()

      %PlatformOperator{user_id: user.id, added_by_id: user.id}
      |> Repo.insert!()

      app_record = store_manifest_app!(app)

      case store_user_credentials!(user, token_response) do
        {:ok, _credentials} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      %GradePush.Accounts.AuditEvent{}
      |> Ecto.Changeset.cast(
        %{
          scope: :platform,
          actor_id: user.id,
          action: "installation.initialized",
          target_type: "institution",
          target_id: institution.id,
          target_label: institution.name,
          metadata: %{"github_app_id" => Integer.to_string(app_record.app_id)}
        },
        [:scope, :actor_id, :action, :target_type, :target_id, :target_label, :metadata]
      )
      |> Ecto.Changeset.validate_required([:scope, :actor_id, :action, :target_type])
      |> Repo.insert!()

      Repo.delete!(bootstrap)
      {:ok, session_token} = Accounts.create_session(user)

      %{user: user, institution: institution, session_token: session_token}
    end)
  end
end
