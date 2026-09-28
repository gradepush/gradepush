defmodule GradePush.CLI do
  @moduledoc "Device authorization and scoped repository manifests for the GradePush CLI."

  import Ecto.Query

  alias GradePush.Accounts
  alias GradePush.Accounts.User
  alias GradePush.Assignments.{Assignment, Repository, Subject}
  alias GradePush.Classrooms
  alias GradePush.CLI.{AccessToken, DeviceAuthorization, RateLimiter}
  alias GradePush.Crypto
  alias GradePush.Demo
  alias GradePush.Repo

  @device_lifetime_seconds 600
  @device_poll_interval_seconds 5
  @access_token_lifetime_seconds 60 * 60 * 24 * 90
  @poll_interval_step_seconds 5
  @user_code_alphabet "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @user_code_pattern ~r/\A[A-HJ-NP-Z2-9]{10}\z/
  @slug_pattern ~r/\A[a-z0-9][a-z0-9_-]{0,99}\z/

  @doc "Creates a short-lived device authorization request for the CLI client."
  def request_device(client_key)
      when is_binary(client_key) and byte_size(client_key) in 1..100 do
    with :ok <- ensure_cli_enabled(),
         true <- String.valid?(client_key),
         client_key <- String.trim(client_key),
         true <- client_key != "",
         :ok <- rate_limit({:device, client_key}, 60, 60),
         :ok <- cleanup_expired_records(utc_now()),
         {:ok, device_code, user_code, _authorization} <- insert_device_authorization() do
      {:ok,
       %{
         device_code: device_code,
         user_code: user_code,
         expires_in: @device_lifetime_seconds,
         interval: @device_poll_interval_seconds
       }}
    else
      false -> {:error, :invalid_client}
      {:error, _reason} = error -> error
    end
  end

  def request_device(_client_key), do: {:error, :invalid_client}

  @doc "Approves a pending device request for an institution teacher."
  def approve(%User{} = actor, user_code) do
    with :ok <- ensure_approval_enabled(),
         :ok <- rate_limit({:authorization_attempt, actor.id}, 15, 60),
         {:ok, user_code_hash} <- user_code_hash(user_code) do
      change_device_authorization(user_code_hash, actor.id, :approve)
    end
  end

  def approve(_actor, _user_code), do: {:error, :unauthorized}

  @doc "Denies a pending device request for an institution teacher."
  def deny(%User{} = actor, user_code) do
    with :ok <- ensure_approval_enabled(),
         :ok <- rate_limit({:authorization_attempt, actor.id}, 15, 60),
         {:ok, user_code_hash} <- user_code_hash(user_code) do
      change_device_authorization(user_code_hash, actor.id, :deny)
    end
  end

  def deny(_actor, _user_code), do: {:error, :unauthorized}

  @doc "Polls a device authorization and creates its one-time CLI token after approval."
  def poll_device(device_code), do: poll_device(device_code, "direct-client")

  def poll_device(device_code, client_key)
      when is_binary(device_code) and byte_size(device_code) <= 128 and is_binary(client_key) and
             byte_size(client_key) <= 100 do
    with :ok <- ensure_cli_enabled(),
         {:ok, device_code_hash} <- device_code_hash(device_code),
         :ok <- rate_limit({:poll_ip, client_key}, 120, 60),
         :ok <- rate_limit({:poll_device, device_code_hash}, 12, 60) do
      Repo.transaction(fn -> poll_device_locked(device_code_hash) end)
      |> transaction_result()
    end
  end

  def poll_device(_device_code, _client_key), do: {:error, :invalid_grant}

  @doc "Authenticates an active CLI token and rechecks its owner's current teacher role."
  def authenticate_access_token(token)
      when is_binary(token) and byte_size(token) in 1..128 do
    if ensure_cli_enabled() == :ok do
      token_hash = Crypto.hash(token)
      now = DateTime.utc_now()

      user =
        Repo.one(
          from(access_token in AccessToken,
            join: user in assoc(access_token, :user),
            where:
              access_token.token_hash == ^token_hash and is_nil(access_token.revoked_at) and
                access_token.expires_at > ^now,
            select: user,
            limit: 1
          )
        )

      if require_teacher(user) == :ok do
        user
      else
        revoke_access_token(token)
        nil
      end
    else
      nil
    end
  end

  def authenticate_access_token(_token), do: nil

  @doc "Revokes an active CLI token without touching browser sessions."
  def revoke_access_token(token) when is_binary(token) and byte_size(token) <= 128 do
    with :ok <- ensure_cli_enabled() do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      from(access_token in AccessToken,
        where: access_token.token_hash == ^Crypto.hash(token) and is_nil(access_token.revoked_at)
      )
      |> Repo.update_all(set: [revoked_at: now])

      :ok
    end
  end

  def revoke_access_token(_token), do: :ok

  @doc "Returns a teacher-authorized page of ready repositories for one classroom."
  def list_repositories(actor, classroom_slug, opts \\ [])

  def list_repositories(%User{} = actor, classroom_slug, opts) when is_list(opts) do
    assignment_slug = Keyword.get(opts, :assignment)
    page = Keyword.get(opts, :page, 1)

    with :ok <- ensure_cli_enabled(),
         :ok <- require_teacher(actor),
         :ok <- validate_slug(classroom_slug),
         :ok <- validate_optional_slug(assignment_slug),
         :ok <- validate_page(page),
         {:ok, classroom} <- Classrooms.get_classroom(actor, classroom_slug) do
      page_repositories(classroom_slug, classroom.id, assignment_slug, page)
    end
  end

  def list_repositories(_actor, _classroom_slug, _opts), do: {:error, :unauthorized}

  defp insert_device_authorization do
    device_code = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    user_code = generate_user_code()
    now = utc_now()

    attrs = %{
      device_code_hash: Crypto.hash(device_code),
      user_code_hash: user_code |> normalize_user_code() |> Crypto.hash(),
      status: "pending",
      expires_at: DateTime.add(now, @device_lifetime_seconds, :second),
      poll_interval_seconds: @device_poll_interval_seconds
    }

    case %DeviceAuthorization{}
         |> DeviceAuthorization.changeset(attrs)
         |> Repo.insert() do
      {:ok, authorization} -> {:ok, device_code, user_code, authorization}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp change_device_authorization(user_code_hash, actor_id, action) do
    now = utc_now()

    Repo.transaction(fn ->
      actor = Repo.one(from(user in User, where: user.id == ^actor_id, lock: "FOR UPDATE"))
      unless require_teacher(actor) == :ok, do: Repo.rollback(:unauthorized)

      authorization =
        Repo.one(
          from(device in DeviceAuthorization,
            where: device.user_code_hash == ^user_code_hash,
            lock: "FOR UPDATE"
          )
        ) || Repo.rollback(:invalid_user_code)

      cond do
        DateTime.compare(authorization.expires_at, now) != :gt ->
          Repo.rollback(:expired_request)

        authorization.status != "pending" ->
          Repo.rollback(:request_already_handled)

        action == :approve ->
          authorization
          |> DeviceAuthorization.changeset(%{
            status: "approved",
            user_id: actor.id,
            approved_at: now
          })
          |> Repo.update!()

        action == :deny ->
          authorization
          |> DeviceAuthorization.changeset(%{status: "denied", denied_at: now})
          |> Repo.update!()
      end

      :ok
    end)
    |> transaction_result()
  end

  defp poll_device_locked(device_code_hash) do
    now = utc_now()

    snapshot =
      Repo.one(
        from(device in DeviceAuthorization, where: device.device_code_hash == ^device_code_hash)
      ) ||
        Repo.rollback(:invalid_grant)

    locked_user = lock_approved_user(snapshot)

    authorization =
      Repo.one(
        from(device in DeviceAuthorization,
          where: device.device_code_hash == ^device_code_hash,
          lock: "FOR UPDATE"
        )
      ) || Repo.rollback(:invalid_grant)

    cond do
      DateTime.compare(authorization.expires_at, now) != :gt ->
        Repo.rollback(:expired_token)

      authorization.status == "denied" ->
        Repo.rollback(:access_denied)

      authorization.status == "consumed" ->
        Repo.rollback(:invalid_grant)

      authorization.status not in ["pending", "approved"] ->
        Repo.rollback(:invalid_grant)

      true ->
        poll_pending_or_approved(authorization, now, locked_user)
    end
  end

  defp lock_approved_user(%DeviceAuthorization{status: "approved", user_id: user_id})
       when is_integer(user_id) do
    Repo.one(from(user in User, where: user.id == ^user_id, lock: "FOR UPDATE"))
  end

  defp lock_approved_user(_authorization), do: nil

  defp poll_pending_or_approved(authorization, now, locked_user) do
    last_poll = authorization.last_polled_at || authorization.inserted_at
    elapsed_seconds = DateTime.diff(now, last_poll, :microsecond) / 1_000_000

    if elapsed_seconds < authorization.poll_interval_seconds do
      authorization
      |> DeviceAuthorization.changeset(%{
        poll_interval_seconds:
          min(authorization.poll_interval_seconds + @poll_interval_step_seconds, 3600),
        last_polled_at: now
      })
      |> Repo.update!()

      {:error, :slow_down}
    else
      authorization
      |> DeviceAuthorization.changeset(%{last_polled_at: now})
      |> Repo.update!()

      case authorization.status do
        "pending" -> {:error, :authorization_pending}
        "approved" when is_nil(locked_user) -> {:error, :authorization_pending}
        "approved" -> issue_access_token(authorization, locked_user, now)
      end
    end
  end

  defp issue_access_token(%DeviceAuthorization{user_id: user_id} = authorization, user, now)
       when is_integer(user_id) and is_struct(user, User) do
    if user.id == user_id and require_teacher(user) == :ok do
      :ok = cleanup_expired_records(now)
      access_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

      %AccessToken{}
      |> AccessToken.changeset(%{
        user_id: user_id,
        token_hash: Crypto.hash(access_token),
        expires_at: DateTime.add(now, @access_token_lifetime_seconds, :second)
      })
      |> Repo.insert!()

      authorization
      |> DeviceAuthorization.changeset(%{status: "consumed", consumed_at: now})
      |> Repo.update!()

      {:ok,
       %{
         access_token: access_token,
         token_type: "Bearer",
         expires_in: @access_token_lifetime_seconds
       }}
    else
      authorization
      |> DeviceAuthorization.changeset(%{status: "denied", denied_at: now})
      |> Repo.update!()

      {:error, :access_denied}
    end
  end

  defp issue_access_token(_authorization, _user, _now), do: {:error, :invalid_grant}

  defp page_repositories(classroom_slug, classroom_id, assignment_slug, page) do
    offset = (page - 1) * 100

    query =
      from(assignment in Assignment,
        join: classroom in assoc(assignment, :classroom),
        join: subject in Subject,
        on: subject.assignment_id == assignment.id,
        join: repository in Repository,
        on: repository.subject_id == subject.id,
        where:
          classroom.id == ^classroom_id and classroom.slug == ^classroom_slug and
            is_nil(classroom.archived_at) and is_nil(assignment.archived_at) and
            repository.state == "ready" and not is_nil(repository.full_name),
        order_by: [asc: assignment.slug, asc: repository.full_name],
        distinct: true,
        limit: 101,
        offset: ^offset,
        select: {assignment.slug, repository.full_name}
      )

    query =
      if is_binary(assignment_slug) do
        from([assignment, classroom, subject, repository] in query,
          where: assignment.slug == ^assignment_slug
        )
      else
        query
      end

    rows = Repo.all(query)
    page_rows = Enum.take(rows, 100)

    {:ok,
     %{
       schema_version: 1,
       classroom: %{slug: classroom_slug},
       repositories:
         Enum.map(page_rows, fn {slug, full_name} -> %{assignment: slug, full_name: full_name} end),
       next_page: if(length(rows) > 100, do: page + 1, else: nil)
     }}
  end

  defp user_code_hash(value) when is_binary(value) and byte_size(value) <= 32 do
    if String.valid?(value) do
      normalized = normalize_user_code(value)

      if Regex.match?(@user_code_pattern, normalized),
        do: {:ok, Crypto.hash(normalized)},
        else: {:error, :invalid_user_code}
    else
      {:error, :invalid_user_code}
    end
  end

  defp user_code_hash(_value), do: {:error, :invalid_user_code}

  defp device_code_hash(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, decoded} when byte_size(decoded) == 32 -> {:ok, Crypto.hash(value)}
      _other -> {:error, :invalid_grant}
    end
  end

  defp normalize_user_code(value) do
    value
    |> String.upcase()
    |> String.replace(~r/[\s-]/u, "")
  end

  defp generate_user_code do
    :crypto.strong_rand_bytes(10)
    |> then(fn bytes ->
      for <<byte <- bytes>>, into: "", do: binary_part(@user_code_alphabet, rem(byte, 32), 1)
    end)
    |> String.codepoints()
    |> Enum.chunk_every(5)
    |> Enum.map_join("-", &Enum.join/1)
  end

  defp require_teacher(%User{} = actor) do
    if Accounts.teacher?(actor), do: :ok, else: {:error, :unauthorized}
  end

  defp require_teacher(_actor), do: {:error, :unauthorized}

  defp ensure_cli_enabled do
    if Demo.enabled?(), do: {:error, :unavailable_in_demo}, else: :ok
  end

  defp ensure_approval_enabled do
    ensure_cli_enabled()
  end

  defp rate_limit(key, limit, window_seconds) do
    case RateLimiter.allow?(key, limit, window_seconds) do
      :ok -> :ok
      {:error, _retry_after_ms} -> {:error, :rate_limited}
    end
  end

  defp cleanup_expired_records(now) do
    device_retention_cutoff = DateTime.add(now, -24 * 60 * 60, :second)

    from(device in DeviceAuthorization, where: device.expires_at < ^device_retention_cutoff)
    |> Repo.delete_all()

    from(access_token in AccessToken,
      where:
        access_token.expires_at <= ^now or
          (not is_nil(access_token.revoked_at) and access_token.revoked_at <= ^now)
    )
    |> Repo.delete_all()

    :ok
  end

  defp validate_slug(value) when is_binary(value) and byte_size(value) <= 100 do
    if String.valid?(value) and Regex.match?(@slug_pattern, value),
      do: :ok,
      else: {:error, :invalid_request}
  end

  defp validate_slug(_value), do: {:error, :invalid_request}

  defp validate_optional_slug(nil), do: :ok
  defp validate_optional_slug(value), do: validate_slug(value)

  defp validate_page(page) when is_integer(page) and page in 1..1_000_000, do: :ok
  defp validate_page(_page), do: {:error, :invalid_request}

  defp transaction_result({:ok, result}), do: result
  defp transaction_result({:error, reason}), do: {:error, reason}

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
