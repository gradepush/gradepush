defmodule GradePush.Accounts do
  @moduledoc """
  Manages GitHub identities, institution membership, operator access, and sessions.
  """

  import Ecto.Query

  alias GradePush.Accounts.{
    AuditEvent,
    Institution,
    InstitutionInvitation,
    InstitutionMembership,
    PlatformOperator,
    User,
    UserSession
  }

  alias GradePush.Crypto
  alias GradePush.Demo
  alias GradePush.Repo

  @session_lifetime_seconds 60 * 60 * 24 * 60
  @invitation_lifetime_seconds 60 * 60 * 24 * 7

  def get_user(id) when is_integer(id) do
    case Repo.get(User, id) do
      nil -> nil
      user -> with_student_profile(user)
    end
  end

  def get_user(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> get_user(integer)
      _other -> nil
    end
  end

  def get_user(_id), do: nil

  def upsert_github_user(attrs) when is_map(attrs) do
    normalized = %{
      github_id: value(attrs, :github_id, :id),
      login: value(attrs, :login, :login),
      name: value(attrs, :name, :name),
      avatar_url: value(attrs, :avatar_url, :avatar_url)
    }

    changeset = User.changeset(%User{}, normalized)

    Repo.insert(changeset,
      on_conflict: {:replace, [:login, :name, :avatar_url, :updated_at]},
      conflict_target: [:github_id],
      returning: true
    )
    |> case do
      {:ok, user} -> {:ok, with_student_profile(user)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def create_session(user, opts \\ [])

  def create_session(%User{id: user_id}, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    lifetime = Keyword.get(opts, :lifetime_seconds, @session_lifetime_seconds)
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    attrs = %{
      user_id: user_id,
      token_hash: Crypto.hash(token),
      expires_at: DateTime.add(now, lifetime, :second)
    }

    with {:ok, _session} <-
           %UserSession{}
           |> UserSession.changeset(attrs)
           |> Repo.insert() do
      cleanup_expired_sessions(now)
      {:ok, token}
    end
  end

  def create_session(_user, _opts), do: {:error, :invalid_user}

  def get_user_by_session_token(token) when is_binary(token) and byte_size(token) <= 128 do
    token_hash = Crypto.hash(token)
    now = DateTime.utc_now()

    query =
      from session in UserSession,
        join: user in assoc(session, :user),
        where:
          session.token_hash == ^token_hash and is_nil(session.revoked_at) and
            session.expires_at > ^now,
        select: user,
        limit: 1

    query
    |> Repo.one()
    |> case do
      nil -> nil
      user -> with_student_profile(user)
    end
  end

  def get_user_by_session_token(_token), do: nil

  def revoke_session(token) when is_binary(token) and byte_size(token) <= 128 do
    token_hash = Crypto.hash(token)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {count, _} =
      from(session in UserSession,
        where: session.token_hash == ^token_hash and is_nil(session.revoked_at)
      )
      |> Repo.update_all(set: [revoked_at: now])

    if count > 0, do: broadcast_session_revoked(token_hash)

    :ok
  end

  def revoke_session(_token), do: :ok

  def watch_session(token) when is_binary(token) and byte_size(token) <= 128 do
    token_hash = Crypto.hash(token)
    topic = session_topic(token_hash)
    :ok = Phoenix.PubSub.subscribe(GradePush.PubSub, topic)
    now = DateTime.utc_now()

    case Repo.one(
           from(session in UserSession,
             where:
               session.token_hash == ^token_hash and is_nil(session.revoked_at) and
                 session.expires_at > ^now,
             select: session.expires_at
           )
         ) do
      %DateTime{} = expires_at ->
        {:ok, expires_at}

      nil ->
        Phoenix.PubSub.unsubscribe(GradePush.PubSub, topic)
        {:error, :invalid_session}
    end
  end

  def watch_session(_token), do: {:error, :invalid_session}

  def revoke_user_sessions(user_id) when is_integer(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    hashes =
      from(session in UserSession,
        where: session.user_id == ^user_id and is_nil(session.revoked_at),
        select: session.token_hash
      )
      |> Repo.all()

    from(session in UserSession,
      where: session.user_id == ^user_id and is_nil(session.revoked_at)
    )
    |> Repo.update_all(set: [revoked_at: now])

    Enum.each(hashes, &broadcast_session_revoked/1)
    :ok
  end

  def broadcast_session_revoked(token_hash) when is_binary(token_hash) do
    Phoenix.PubSub.broadcast(
      GradePush.PubSub,
      session_topic(token_hash),
      :gradepush_session_revoked
    )
  end

  def institution, do: Repo.one(Institution)

  def footer_links do
    Repo.one(from(i in Institution, select: map(i, ^Institution.footer_fields()))) || %{}
  end

  def change_footer_links(links, attrs \\ %{}) do
    Institution.footer_changeset(struct(Institution, links), attrs)
  end

  def update_footer_links(actor, attrs) when is_map(attrs) do
    if admin?(actor),
      do: Repo.transaction(fn -> update_footer_links_locked!(actor, attrs) end),
      else: {:error, :unauthorized}
  end

  defp update_footer_links_locked!(actor, attrs) do
    institution = Repo.one(from(i in Institution, lock: "FOR UPDATE"))
    unless admin?(actor), do: Repo.rollback(:unauthorized)

    case institution |> Institution.footer_changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        record_audit(
          actor,
          :institution,
          "institution.footer_updated",
          "institution",
          updated.id,
          updated.name,
          %{}
        )
        |> audit_result!()

        Map.take(updated, Institution.footer_fields())

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  def institution_role(actor) do
    case membership_roles(actor) do
      [] ->
        nil

      roles ->
        Enum.find(roles, &(&1 == :admin)) ||
          Enum.find(roles, &(&1 == :teacher)) ||
          Enum.find(roles, &(&1 == :student))
    end
  end

  def institution_roles(actor), do: membership_roles(actor)

  def teacher?(actor), do: has_role?(actor, :teacher)
  def student?(actor), do: has_role?(actor, :student)
  def admin?(actor), do: has_role?(actor, :admin)

  def operator?(%User{id: user_id}) when is_integer(user_id) do
    Repo.exists?(from operator in PlatformOperator, where: operator.user_id == ^user_id)
  end

  def operator?(_actor), do: false

  def institution_teachers(actor) do
    if institution_member?(actor) do
      institution_id = institution_id()

      teacher_ids =
        from(membership in InstitutionMembership,
          where:
            membership.institution_id == ^institution_id and
              membership.role in [:teacher, :admin],
          select: membership.user_id
        )

      users =
        from(user in User,
          where: user.id in subquery(teacher_ids),
          order_by: [asc: fragment("lower(?)", user.login)]
        )
        |> Repo.all()

      {:ok, users}
    else
      {:error, :unauthorized}
    end
  end

  def find_teacher(actor, login) when is_binary(login) do
    if institution_member?(actor) do
      normalized_login = String.downcase(login)
      institution_id = institution_id()

      query =
        from(user in User,
          join: membership in InstitutionMembership,
          on: membership.user_id == user.id,
          where:
            membership.institution_id == ^institution_id and
              membership.role in [:teacher, :admin] and
              fragment("lower(?)", user.login) == ^normalized_login,
          limit: 1
        )

      case Repo.one(query) do
        nil -> {:error, :not_found}
        user -> {:ok, with_student_profile(user)}
      end
    else
      {:error, :unauthorized}
    end
  end

  def find_teacher(_actor, _login), do: {:error, :not_found}

  def with_student_profiles(users) when is_list(users) do
    user_ids = users |> Enum.map(& &1.id) |> Enum.filter(&is_integer/1) |> Enum.uniq()

    profiles =
      case {institution_id(), user_ids} do
        {nil, _ids} ->
          %{}

        {_institution_id, []} ->
          %{}

        {institution_id, ids} ->
          from(membership in InstitutionMembership,
            where:
              membership.institution_id == ^institution_id and membership.user_id in ^ids and
                membership.role == :student,
            select: {membership.user_id, membership.student_name, membership.student_id}
          )
          |> Repo.all()
          |> Map.new(fn {user_id, name, student_id} ->
            {user_id, %{student_name: name, student_id: student_id}}
          end)
      end

    Enum.map(users, fn
      %User{id: user_id} = user ->
        case Map.fetch(profiles, user_id) do
          {:ok, profile} -> Map.merge(user, profile)
          :error -> user
        end

      other ->
        other
    end)
  end

  def with_student_profiles(_users), do: []

  def list_teachers(actor) do
    if admin?(actor) do
      {:ok, list_institution_teachers(institution_id())}
    else
      {:error, :unauthorized}
    end
  end

  defp list_institution_teachers(institution_id) do
    from(user in User,
      join: membership in InstitutionMembership,
      on: membership.user_id == user.id,
      where:
        membership.institution_id == ^institution_id and membership.role in [:teacher, :admin],
      order_by: [asc: fragment("lower(?)", user.login)],
      select: {user, membership.role}
    )
    |> Repo.all()
    |> Enum.group_by(fn {user, _role} -> user.id end)
    |> Enum.map(fn {_id, entries} ->
      {users, roles} = Enum.unzip(entries)
      role = if :admin in roles, do: :admin, else: :teacher
      %{user: hd(users), role: role, classrooms: 0}
    end)
  end

  def institution_stats(actor) do
    if admin?(actor) do
      institution_id = institution_id()

      counts =
        from(membership in InstitutionMembership,
          where: membership.institution_id == ^institution_id,
          group_by: membership.role,
          select: {membership.role, count(membership.id)}
        )
        |> Repo.all()
        |> Map.new()

      {:ok,
       %{
         admins: Map.get(counts, :admin, 0),
         teachers: Map.get(counts, :teacher, 0),
         students: Map.get(counts, :student, 0)
       }}
    else
      {:error, :unauthorized}
    end
  end

  def create_teacher_invitation(actor) do
    with :ok <- Demo.ensure_invitations_enabled(),
         true <- admin?(actor),
         %Institution{id: institution_id} <- institution() do
      persist_teacher_invitation(actor, institution_id)
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :institution_not_configured}
      {:error, _} = error -> error
    end
  end

  defp persist_teacher_invitation(actor, institution_id) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.transaction(fn ->
      _locked_institution = Repo.one(from(i in Institution, lock: "FOR UPDATE"))
      ensure_institution_admin!(actor)

      invitation =
        %InstitutionInvitation{}
        |> InstitutionInvitation.changeset(%{
          institution_id: institution_id,
          invited_by_id: actor.id,
          token_hash: Crypto.hash(token),
          expires_at: DateTime.add(now, @invitation_lifetime_seconds, :second)
        })
        |> Repo.insert!()

      :ok =
        record_audit(
          actor,
          :institution,
          "teacher.invited",
          "invitation",
          invitation.id,
          "Teacher invitation",
          %{}
        )
        |> audit_result!()

      %{invitation: invitation, token: token}
    end)
  end

  defp ensure_institution_admin!(actor) do
    unless admin?(actor), do: Repo.rollback(:unauthorized)
  end

  def lookup_teacher_invitation(token) when is_binary(token) and byte_size(token) <= 128 do
    with :ok <- Demo.ensure_invitations_enabled() do
      case active_invitation(token) do
        nil ->
          {:error, :invalid_invitation}

        invitation ->
          {:ok,
           %{
             institution_name: institution().name,
             expires_at: invitation.expires_at
           }}
      end
    end
  end

  def lookup_teacher_invitation(_token), do: {:error, :invalid_invitation}

  def valid_teacher_invitation?(token) do
    match?({:ok, _metadata}, lookup_teacher_invitation(token))
  end

  def accept_teacher_invitation(%User{id: user_id} = actor, token)
      when is_integer(user_id) and is_binary(token) do
    with :ok <- Demo.ensure_invitations_enabled() do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      hash = Crypto.hash(token)

      Repo.transaction(fn ->
        invitation = lock_valid_invitation!(hash, now)
        member = get_or_insert_teacher_membership!(invitation, actor, now)
        mark_invitation_accepted!(invitation, actor, now)
        member
      end)
    end
  end

  def accept_teacher_invitation(_actor, _token), do: {:error, :invalid_invitation}

  defp lock_valid_invitation!(hash, now) do
    invitation =
      from(invitation in InstitutionInvitation,
        where: invitation.token_hash == ^hash,
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    valid? =
      not is_nil(invitation) and is_nil(invitation.revoked_at) and
        is_nil(invitation.accepted_at) and DateTime.compare(invitation.expires_at, now) == :gt

    if valid?, do: invitation, else: Repo.rollback(:invalid_invitation)
  end

  defp get_or_insert_teacher_membership!(invitation, actor, now) do
    attrs = %{
      institution_id: invitation.institution_id,
      user_id: actor.id,
      role: :teacher,
      joined_at: now
    }

    case Repo.get_by(InstitutionMembership,
           institution_id: invitation.institution_id,
           user_id: actor.id,
           role: :teacher
         ) do
      %InstitutionMembership{} = membership ->
        membership

      nil ->
        case %InstitutionMembership{}
             |> InstitutionMembership.changeset(attrs)
             |> Repo.insert(
               on_conflict: :nothing,
               conflict_target: [:institution_id, :user_id, :role],
               returning: true
             ) do
          {:ok, %InstitutionMembership{id: id} = membership} when not is_nil(id) ->
            membership

          {:ok, _conflict} ->
            Repo.get_by!(InstitutionMembership,
              institution_id: invitation.institution_id,
              user_id: actor.id,
              role: :teacher
            )

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
    end
  end

  defp mark_invitation_accepted!(invitation, actor, now) do
    invitation
    |> InstitutionInvitation.changeset(%{accepted_by_id: actor.id, accepted_at: now})
    |> Repo.update!()

    :ok =
      record_audit(
        actor,
        :institution,
        "teacher.invitation.accepted",
        "user",
        actor.id,
        actor.login,
        %{}
      )
      |> audit_result!()
  end

  def change_role(actor, user_id, role) when role in ["admin", "teacher", :admin, :teacher] do
    with true <- admin?(actor),
         %User{} = target <- get_user(user_id),
         true <- teacher_or_admin?(target) do
      new_role = if role in ["admin", :admin], do: :admin, else: :teacher
      current_role = if admin?(target), do: :admin, else: :teacher

      if new_role == current_role do
        {:ok, target}
      else
        change_institution_role(actor, target, new_role)
      end
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :not_found}
    end
  end

  def change_role(_actor, _user_id, _role), do: {:error, :invalid_role}

  def remove_teacher(actor, user_id) do
    parsed_user_id = parse_id(user_id)

    cond do
      not admin?(actor) ->
        {:error, :unauthorized}

      is_nil(parsed_user_id) ->
        {:error, :not_found}

      actor_id(actor) == parsed_user_id ->
        {:error, :cannot_remove_self}

      true ->
        remove_teacher_target(actor, parsed_user_id)
    end
  end

  defp remove_teacher_target(actor, user_id) do
    case get_user(user_id) do
      %User{} = target ->
        if teacher_or_admin?(target),
          do: remove_institution_teacher(actor, target),
          else: {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  def rename_institution(actor, name) when is_binary(name) do
    with true <- admin?(actor),
         %Institution{} = institution <- institution() do
      rename_institution_record(actor, institution, name)
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :institution_not_configured}
    end
  end

  def rename_institution(_actor, _name), do: {:error, :invalid_name}

  defp rename_institution_record(actor, institution, name) do
    Repo.transaction(fn ->
      _locked_institution = Repo.one(from(i in Institution, lock: "FOR UPDATE"))

      unless admin?(actor), do: Repo.rollback(:unauthorized)

      updated =
        institution
        |> Institution.changeset(%{name: name})
        |> Repo.update!()

      :ok =
        record_audit(
          actor,
          :institution,
          "institution.renamed",
          "institution",
          updated.id,
          updated.name,
          %{}
        )
        |> audit_result!()

      updated
    end)
  end

  def list_audit(actor, scope) when scope in [:institution, :platform] do
    authorized? = if scope == :institution, do: admin?(actor), else: operator?(actor)

    if authorized? do
      events =
        from(event in AuditEvent,
          left_join: user in assoc(event, :actor),
          where: event.scope == ^scope,
          order_by: [desc: event.inserted_at, desc: event.id],
          limit: 250,
          select: {event, user.name, user.login}
        )
        |> Repo.all()
        |> Enum.map(fn {event, name, login} ->
          %{
            actor_name: name || login || "System",
            action: event.action,
            target: event.target_label,
            inserted_at: event.inserted_at
          }
        end)

      {:ok, events}
    else
      {:error, :unauthorized}
    end
  end

  def list_audit(_actor, _scope), do: {:error, :unauthorized}

  def record_audit(actor, scope, action, target_type, target_id, target_label, metadata \\ %{})

  def record_audit(actor, scope, action, target_type, target_id, target_label, metadata)
      when scope in [:institution, :platform] and is_binary(action) and is_binary(target_type) and
             is_map(metadata) do
    authorized? =
      case scope do
        :institution -> institution_member?(actor)
        :platform -> operator?(actor)
      end

    if authorized? do
      %AuditEvent{}
      |> Ecto.Changeset.cast(
        %{
          scope: scope,
          actor_id: actor.id,
          action: action,
          target_type: target_type,
          target_id: target_id,
          target_label: target_label,
          metadata: metadata
        },
        [:scope, :actor_id, :action, :target_type, :target_id, :target_label, :metadata]
      )
      |> Ecto.Changeset.validate_required([:scope, :action, :target_type])
      |> Ecto.Changeset.validate_length(:action, max: 100)
      |> Ecto.Changeset.validate_length(:target_type, max: 100)
      |> Ecto.Changeset.validate_length(:target_label, max: 255)
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  def record_audit(_actor, _scope, _action, _target_type, _target_id, _target_label, _metadata),
    do: {:error, :invalid_audit_event}

  def enroll_student(%User{id: user_id}, attrs) when is_integer(user_id) and is_map(attrs) do
    with %Institution{id: institution_id} <- institution(),
         name when is_binary(name) <- value(attrs, :name, :name) |> trim_if_binary(),
         student_id when is_binary(student_id) <-
           value(attrs, :student_id, :student_id) |> trim_if_binary(),
         true <- String.length(name) in 1..255,
         true <- String.length(student_id) in 1..100 do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      %InstitutionMembership{}
      |> InstitutionMembership.changeset(%{
        institution_id: institution_id,
        user_id: user_id,
        role: :student,
        student_name: name,
        student_id: student_id,
        joined_at: now
      })
      |> Repo.insert(
        on_conflict: [set: [student_name: name, student_id: student_id, updated_at: now]],
        conflict_target: [:institution_id, :user_id, :role],
        returning: true
      )
    else
      nil -> {:error, :institution_not_configured}
      false -> {:error, :invalid_student_profile}
      _other -> {:error, :invalid_student_profile}
    end
  end

  def enroll_student(_actor, _attrs), do: {:error, :invalid_user}

  def student_profile(actor) do
    case student_membership(actor) do
      nil -> nil
      membership -> %{name: membership.student_name, student_id: membership.student_id}
    end
  end

  def update_locale(%User{id: user_id}, locale) when locale in ["en", "fr"] do
    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      user -> user |> User.changeset(%{locale: locale}) |> Repo.update()
    end
  end

  def update_locale(_actor, _locale), do: {:error, :invalid_locale}

  defp change_institution_role(actor, target, role) do
    institution_id = institution_id()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.transaction(fn ->
      _locked_institution = Repo.one(from(i in Institution, lock: "FOR UPDATE"))

      unless admin?(actor), do: Repo.rollback(:unauthorized)
      unless teacher_or_admin?(target), do: Repo.rollback(:not_found)

      current_role = if admin?(target), do: :admin, else: :teacher
      admin_count = count_role(:admin)

      if current_role == :admin and admin_count <= 1 do
        Repo.rollback(:last_administrator)
      end

      if current_role == role,
        do: get_user(target.id),
        else: persist_institution_role(actor, target, institution_id, role, current_role, now)
    end)
  end

  defp persist_institution_role(actor, target, institution_id, role, current_role, now) do
    case role do
      :admin ->
        %InstitutionMembership{}
        |> InstitutionMembership.changeset(%{
          institution_id: institution_id,
          user_id: target.id,
          role: :admin,
          joined_at: now
        })
        |> Repo.insert!(
          on_conflict: :nothing,
          conflict_target: [:institution_id, :user_id, :role]
        )

      :teacher ->
        from(membership in InstitutionMembership,
          where:
            membership.institution_id == ^institution_id and membership.user_id == ^target.id and
              membership.role == :admin
        )
        |> Repo.delete_all()

        %InstitutionMembership{}
        |> InstitutionMembership.changeset(%{
          institution_id: institution_id,
          user_id: target.id,
          role: :teacher,
          joined_at: now
        })
        |> Repo.insert!(
          on_conflict: :nothing,
          conflict_target: [:institution_id, :user_id, :role]
        )
    end

    action = if role == :admin, do: "teacher.admin_granted", else: "teacher.admin_revoked"

    :ok =
      record_audit(actor, :institution, action, "user", target.id, target.login, %{
        "from" => Atom.to_string(current_role),
        "to" => Atom.to_string(role)
      })
      |> audit_result!()

    get_user(target.id)
  end

  defp remove_institution_teacher(actor, target) do
    institution_id = institution_id()

    Repo.transaction(fn ->
      _locked_institution = Repo.one(from(i in Institution, lock: "FOR UPDATE"))

      unless admin?(actor), do: Repo.rollback(:unauthorized)
      unless teacher_or_admin?(target), do: Repo.rollback(:not_found)

      if admin?(target) and count_role(:admin) <= 1 do
        Repo.rollback(:last_administrator)
      end

      from(membership in InstitutionMembership,
        where:
          membership.institution_id == ^institution_id and membership.user_id == ^target.id and
            membership.role in [:admin, :teacher]
      )
      |> Repo.delete_all()

      :ok =
        record_audit(
          actor,
          :institution,
          "teacher.removed",
          "user",
          target.id,
          target.login,
          %{}
        )
        |> audit_result!()

      :ok
    end)
  end

  defp active_invitation(token) do
    now = DateTime.utc_now()
    hash = Crypto.hash(token)

    from(invitation in InstitutionInvitation,
      where:
        invitation.token_hash == ^hash and is_nil(invitation.accepted_at) and
          is_nil(invitation.revoked_at) and invitation.expires_at > ^now,
      limit: 1
    )
    |> Repo.one()
  end

  defp has_role?(%User{id: user_id}, role) when is_integer(user_id) do
    institution_id = institution_id()

    not is_nil(institution_id) and
      Repo.exists?(
        from(membership in InstitutionMembership,
          where:
            membership.institution_id == ^institution_id and membership.user_id == ^user_id and
              membership.role == ^role
        )
      )
  end

  defp has_role?(_actor, _role), do: false

  defp institution_member?(actor) do
    Enum.any?(membership_roles(actor), &(&1 in [:admin, :teacher, :student]))
  end

  defp teacher_or_admin?(actor), do: has_role?(actor, :teacher) or has_role?(actor, :admin)

  defp membership_roles(%User{id: user_id}) when is_integer(user_id) do
    case institution_id() do
      nil ->
        []

      institution_id ->
        from(membership in InstitutionMembership,
          where: membership.institution_id == ^institution_id and membership.user_id == ^user_id,
          select: membership.role
        )
        |> Repo.all()
    end
  end

  defp membership_roles(_actor), do: []

  defp student_membership(%User{id: user_id}) when is_integer(user_id) do
    case institution_id() do
      nil ->
        nil

      institution_id ->
        Repo.one(
          from(membership in InstitutionMembership,
            where:
              membership.institution_id == ^institution_id and
                membership.user_id == ^user_id and membership.role == :student,
            limit: 1
          )
        )
    end
  end

  defp student_membership(_actor), do: nil

  defp with_student_profile(%User{} = user) do
    case student_membership(user) do
      nil ->
        user

      membership ->
        %{user | student_name: membership.student_name, student_id: membership.student_id}
    end
  end

  defp institution_id do
    Repo.one(from(institution in Institution, select: institution.id, limit: 1))
  end

  defp count_role(role) do
    institution_id = institution_id()

    Repo.one(
      from(membership in InstitutionMembership,
        where: membership.institution_id == ^institution_id and membership.role == ^role,
        select: count(membership.id)
      )
    )
  end

  defp session_topic(token_hash),
    do: "gradepush:user-session:" <> Base.url_encode64(token_hash, padding: false)

  defp actor_id(%User{id: id}) when is_integer(id), do: id
  defp actor_id(_actor), do: nil

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp parse_id(_id), do: nil

  defp cleanup_expired_sessions(now) do
    cutoff = DateTime.add(now, -@session_lifetime_seconds, :second)

    from(session in UserSession,
      where:
        session.expires_at < ^cutoff or
          (not is_nil(session.revoked_at) and session.revoked_at < ^cutoff)
    )
    |> Repo.delete_all()
  end

  defp audit_result!({:ok, _event}), do: :ok
  defp audit_result!({:error, reason}), do: Repo.rollback(reason)

  defp value(map, key, string_key) do
    Map.get(map, key, Map.get(map, Atom.to_string(string_key)))
  end

  defp trim_if_binary(value) when is_binary(value), do: String.trim(value)
  defp trim_if_binary(value), do: value
end
