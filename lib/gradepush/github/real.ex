defmodule GradePush.GitHub.Real do
  @moduledoc false
  @behaviour GradePush.GitHub

  alias GradePush.GitHub.{Actions, JWT}

  @impl true
  def convert_manifest(code) do
    request(:post, "/app-manifests/#{segment(code)}/conversions", nil, nil)
  end

  @impl true
  def exchange_user_code(code, client_id, client_secret) do
    body = Jason.encode!(%{client_id: client_id, client_secret: client_secret, code: code})
    request_url(:post, github_url("/login/oauth/access_token"), json_headers(), body, nil)
  end

  @impl true
  def get_user(access_token), do: request(:get, "/user", access_token, nil)

  @impl true
  def refresh_user_token(refresh_token, client_id, client_secret) do
    body =
      Jason.encode!(%{
        client_id: client_id,
        client_secret: client_secret,
        grant_type: "refresh_token",
        refresh_token: refresh_token
      })

    request_url(:post, github_url("/login/oauth/access_token"), json_headers(), body, nil)
  end

  @impl true
  def installation_token(credentials, installation_id, options \\ []) do
    with {:ok, jwt} <- JWT.generate(credentials) do
      request(
        :post,
        "/app/installations/#{id(installation_id)}/access_tokens",
        jwt,
        installation_token_body(options)
      )
    end
  end

  @impl true
  def list_installations(credentials) do
    with {:ok, jwt} <- JWT.generate(credentials) do
      request(:get, "/app/installations", jwt, nil)
    end
  end

  @impl true
  def get_installation(credentials, installation_id) do
    with {:ok, jwt} <- JWT.generate(credentials) do
      request(:get, "/app/installations/#{id(installation_id)}", jwt, nil)
    end
  end

  @impl true
  def list_user_installations(access_token) do
    list_all_pages(access_token, "/user/installations", "installations")
  end

  @impl true
  def get_user_installation(access_token, installation_id) do
    with {:ok, installations} <- list_user_installations(access_token) do
      case Enum.find(installations, &(integer_value(&1["id"]) == installation_id)) do
        nil -> {:error, :not_found}
        installation -> {:ok, installation}
      end
    end
  end

  @impl true
  def get_user_organization_membership(access_token, organization)
      when is_binary(organization) and byte_size(organization) in 1..39 do
    request(
      :get,
      "/user/memberships/orgs/#{segment(organization)}",
      access_token,
      nil
    )
  end

  def get_user_organization_membership(_access_token, _organization),
    do: {:error, :invalid_organization}

  @impl true
  def get_user_by_id(access_token, account_id) when is_integer(account_id) and account_id > 0 do
    request(:get, "/user/#{id(account_id)}", access_token, nil)
  end

  def get_user_by_id(_access_token, _account_id), do: {:error, :invalid_github_id}

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp integer_value(_value), do: nil

  @impl true
  def list_user_installation_repositories(access_token, installation_id, options \\ []) do
    if options == [] do
      list_all_pages(
        access_token,
        "/user/installations/#{id(installation_id)}/repositories",
        "repositories"
      )
    else
      query = pagination_query(options)

      request(
        :get,
        "/user/installations/#{id(installation_id)}/repositories?#{query}",
        access_token,
        nil
      )
      |> unwrap_items()
    end
  end

  @impl true
  def list_template_repositories(access_token, organization) do
    list_organization_repositories(access_token, organization, 1, [])
    |> case do
      {:ok, repositories} ->
        {:ok,
         repositories
         |> Enum.filter(& &1["is_template"])
         |> Enum.map(&repository_summary/1)}

      error ->
        error
    end
  end

  @impl true
  def get_repository(access_token, owner, repository) do
    request(:get, repo_path(owner, repository), access_token, nil)
  end

  @impl true
  def create_repository(access_token, organization, attributes) do
    name = Map.get(attributes, :repository_name) || Map.get(attributes, "repository_name")
    template_owner = Map.get(attributes, :template_owner) || Map.get(attributes, "template_owner")
    template_name = Map.get(attributes, :template_name) || Map.get(attributes, "template_name")

    with :ok <- validate_repository_name(name),
         :ok <- validate_repository_visibility(value(attributes, :visibility)),
         :ok <- ensure_repository_available(access_token, organization, name) do
      if template_owner && template_name do
        generate_repository(
          access_token,
          template_owner,
          template_name,
          organization,
          name,
          attributes
        )
      else
        create_empty_repository(access_token, organization, name, attributes)
      end
    end
  end

  @impl true
  def add_collaborator(access_token, owner, repository, username, permission)
      when permission in ["pull", "push"] do
    with :ok <- validate_github_login(username) do
      request(
        :put,
        "#{repo_path(owner, repository)}/collaborators/#{segment(username)}",
        access_token,
        %{permission: permission}
      )
    end
  end

  def add_collaborator(_access_token, _owner, _repository, _username, _permission),
    do: {:error, :invalid_permission}

  @impl true
  def list_commits(access_token, owner, repository, options \\ []) do
    query =
      options
      |> Keyword.take([:sha, :since, :until, :per_page, :page])
      |> URI.encode_query()

    path = "#{repo_path(owner, repository)}/commits?#{query}"
    request(:get, path, access_token, nil) |> unwrap_items()
  end

  @impl true
  def get_workflow_run(access_token, owner, repository, run_id) do
    request(
      :get,
      "#{repo_path(owner, repository)}/actions/runs/#{id(run_id)}",
      access_token,
      nil
    )
  end

  @impl true
  def get_repository_file(access_token, owner, repository, path, ref) do
    query = URI.encode_query(ref: ref)

    request(
      :get,
      "#{repo_path(owner, repository)}/contents/#{path_segment(path)}?#{query}",
      access_token,
      nil
    )
  end

  @impl true
  def list_workflow_jobs(access_token, owner, repository, run_id) do
    request(
      :get,
      "#{repo_path(owner, repository)}/actions/runs/#{id(run_id)}/jobs?per_page=100",
      access_token,
      nil
    )
    |> unwrap_items()
  end

  @impl true
  def install_autograding_workflow(access_token, owner, repository, tests) do
    path = Actions.workflow_path()

    with {:ok, content} <- Actions.generate_workflow(tests),
         {:ok, file} <- ensure_workflow_file(access_token, owner, repository, path, content),
         {:ok, workflow} <-
           request(
             :get,
             "#{repo_path(owner, repository)}/actions/workflows/#{segment(Path.basename(path))}",
             access_token,
             nil
           ),
         workflow_id when is_integer(workflow_id) <- workflow["id"],
         file_sha when is_binary(file_sha) <- workflow_file_sha(file) do
      {:ok,
       %{
         workflow_id: workflow_id,
         workflow_path: path,
         workflow_file_sha: file_sha,
         workflow_commit_sha: get_in(file, ["commit", "sha"])
       }}
    else
      nil -> {:error, :invalid_github_workflow_response}
      false -> {:error, :invalid_github_workflow_response}
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_github_workflow_response}
    end
  end

  defp workflow_file_sha(%{"sha" => sha}) when is_binary(sha), do: sha
  defp workflow_file_sha(%{"content" => %{"sha" => sha}}) when is_binary(sha), do: sha
  defp workflow_file_sha(_file), do: nil

  @impl true
  def put_repository_file(access_token, owner, repository, path, content, attributes) do
    body = %{
      message: Map.get(attributes, :message, "Update file from GradePush"),
      content: Base.encode64(content),
      branch: Map.get(attributes, :branch)
    }

    body = Enum.reject(body, fn {_key, value} -> is_nil(value) end) |> Map.new()

    request(
      :put,
      "#{repo_path(owner, repository)}/contents/#{path_segment(path)}",
      access_token,
      body
    )
  end

  defp ensure_workflow_file(access_token, owner, repository, path, content) do
    case get_repository_file(access_token, owner, repository, path, "HEAD") do
      {:error, {:http_error, 404}} ->
        put_repository_file(access_token, owner, repository, path, content, %{
          message: "Add GradePush autograding workflow"
        })

      {:ok, file} ->
        case decode_file_content(file["content"]) do
          ^content -> {:ok, file}
          _ -> {:error, :workflow_already_exists}
        end

      error ->
        error
    end
  end

  defp decode_file_content(content) when is_binary(content) do
    content
    |> String.replace("\n", "")
    |> Base.decode64()
    |> case do
      {:ok, decoded} -> decoded
      :error -> nil
    end
  end

  defp decode_file_content(_), do: nil

  defp list_organization_repositories(access_token, organization, page, acc) do
    path = "/orgs/#{segment(organization)}/repos?type=all&per_page=100&page=#{page}"

    case request(:get, path, access_token, nil) do
      {:ok, repositories} when is_list(repositories) and length(repositories) == 100 ->
        list_organization_repositories(access_token, organization, page + 1, [repositories | acc])

      {:ok, repositories} when is_list(repositories) ->
        {:ok, [repositories | acc] |> Enum.reverse() |> List.flatten()}

      error ->
        error
    end
  end

  defp list_all_pages(access_token, path, key, page \\ 1, acc \\ [])

  defp list_all_pages(_access_token, _path, _key, page, _acc) when page > 100,
    do: {:error, :pagination_limit}

  defp list_all_pages(access_token, path, key, page, acc) do
    response = request(:get, "#{path}?per_page=100&page=#{page}", access_token, nil)

    with {:ok, items} <- unwrap_collection(response, key) do
      next_acc = Enum.reverse(items, acc)

      if length(items) == 100 do
        list_all_pages(access_token, path, key, page + 1, next_acc)
      else
        {:ok, Enum.reverse(next_acc)}
      end
    end
  end

  defp ensure_repository_available(access_token, organization, name) do
    case get_repository(access_token, organization, name) do
      {:ok, _repository} -> {:error, :repository_name_taken}
      {:error, {:http_error, 404, _}} -> :ok
      {:error, {:http_error, 404}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_repository(access_token, template_owner, template_name, organization, name, attrs) do
    body = %{
      owner: organization,
      name: name,
      private: private?(attrs),
      description: value(attrs, :description),
      include_all_branches: false
    }

    body = Enum.reject(body, fn {_key, value} -> is_nil(value) end) |> Map.new()

    request(
      :post,
      "/repos/#{segment(template_owner)}/#{segment(template_name)}/generate",
      access_token,
      body
    )
  end

  defp create_empty_repository(access_token, organization, name, attrs) do
    body = %{
      name: name,
      private: private?(attrs),
      description: value(attrs, :description),
      has_issues: false,
      has_projects: false,
      has_wiki: false,
      auto_init: true
    }

    body = Enum.reject(body, fn {_key, value} -> is_nil(value) end) |> Map.new()
    request(:post, "/orgs/#{segment(organization)}/repos", access_token, body)
  end

  defp repository_summary(repository) do
    %{
      id: repository["id"],
      name: repository["name"],
      full_name: repository["full_name"],
      description: repository["description"],
      private: repository["private"],
      html_url: repository["html_url"],
      default_branch: repository["default_branch"]
    }
  end

  defp unwrap_items({:ok, %{"repositories" => items}}) when is_list(items), do: {:ok, items}
  defp unwrap_items({:ok, %{"installations" => items}}) when is_list(items), do: {:ok, items}
  defp unwrap_items({:ok, %{"workflow_runs" => items}}) when is_list(items), do: {:ok, items}
  defp unwrap_items({:ok, %{"jobs" => items}}) when is_list(items), do: {:ok, items}
  defp unwrap_items({:ok, items}) when is_list(items), do: {:ok, items}
  defp unwrap_items(error), do: error

  defp unwrap_collection({:ok, %{} = response}, key) do
    case Map.get(response, key) do
      items when is_list(items) -> {:ok, items}
      _ -> {:error, :invalid_github_response}
    end
  end

  defp unwrap_collection({:ok, items}, _key) when is_list(items), do: {:ok, items}
  defp unwrap_collection(error, _key), do: error

  defp installation_token_body(options) do
    repository_ids = Keyword.get(options, :repository_ids)

    case repository_ids do
      ids when is_list(ids) and ids != [] -> %{repository_ids: Enum.map(ids, &repository_id!/1)}
      _ -> %{}
    end
  end

  defp private?(attrs) do
    case value(attrs, :visibility) do
      "public" -> false
      "internal" -> false
      _ -> true
    end
  end

  defp validate_repository_name(name) when is_binary(name) and byte_size(name) in 1..100 do
    if Regex.match?(~r/\A[a-zA-Z0-9._-]+\z/, name),
      do: :ok,
      else: {:error, :invalid_repository_name}
  end

  defp validate_repository_name(_), do: {:error, :invalid_repository_name}

  defp validate_repository_visibility(value) when value in ["private", "public"], do: :ok
  defp validate_repository_visibility(_), do: {:error, :invalid_repository_visibility}

  defp validate_github_login(login)
       when is_binary(login) and byte_size(login) in 1..39 do
    if Regex.match?(~r/\A[a-zA-Z0-9-]+\z/, login),
      do: :ok,
      else: {:error, :invalid_github_login}
  end

  defp validate_github_login(_), do: {:error, :invalid_github_login}

  defp pagination_query(options) do
    options
    |> Keyword.take([:per_page, :page])
    |> Keyword.put_new(:per_page, 100)
    |> URI.encode_query()
  end

  defp request(method, path, token, body) do
    url = api_url(path)
    headers = api_headers(token, body)
    encoded_body = if is_nil(body), do: nil, else: Jason.encode!(body)
    request_url(method, url, headers, encoded_body, token)
  end

  defp request_url(method, url, headers, body, _token) do
    client =
      Application.get_env(:gradepush, GradePush.GitHub, [])
      |> Keyword.get(:http_client, GradePush.GitHub.HTTP)

    client.request(method, url, headers, body)
    |> decode_response()
  end

  defp decode_response({:ok, %{status: status, body: body, headers: headers}})
       when status in 200..299 do
    if body in [nil, "", <<>>] do
      {:ok, nil}
    else
      case Jason.decode(body) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, _} -> {:error, :invalid_github_response}
      end
    end
  rescue
    _ -> {:error, {:http_error, status, rate_limit_delay(headers)}}
  end

  defp decode_response({:ok, %{status: status, headers: headers}}),
    do: decode_http_error(status, headers)

  defp decode_response({:error, reason}),
    do: {:error, {:transport, safe_transport_reason(reason)}}

  defp decode_response(_), do: {:error, :invalid_github_response}

  defp decode_http_error(404, _headers), do: {:error, {:http_error, 404}}
  defp decode_http_error(401, _headers), do: {:error, :unauthorized}
  defp decode_http_error(403, headers), do: forbidden_response(headers)
  defp decode_http_error(429, headers), do: {:error, {:rate_limited, rate_limit_delay(headers)}}

  defp decode_http_error(status, _headers) when status in 500..599,
    do: {:error, {:github_unavailable, status}}

  defp decode_http_error(422, _headers), do: {:error, :unprocessable_entity}
  defp decode_http_error(409, _headers), do: {:error, :conflict}
  defp decode_http_error(status, _headers), do: {:error, {:http_error, status}}

  defp forbidden_response(headers) do
    if rate_limited?(headers),
      do: {:error, {:rate_limited, rate_limit_delay(headers)}},
      else: {:error, :forbidden}
  end

  defp api_headers(token, body) do
    headers = [
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", config(:api_version, "2026-03-10")},
      {"user-agent", "GradePush"}
    ]

    headers = if token, do: [{"authorization", "Bearer " <> token} | headers], else: headers
    if is_nil(body), do: headers, else: [{"content-type", "application/json"} | headers]
  end

  defp json_headers do
    [
      {"accept", "application/json"},
      {"content-type", "application/json"},
      {"user-agent", "GradePush"}
    ]
  end

  defp api_url(path), do: config(:api_url, "https://api.github.com") <> path
  defp github_url(path), do: config(:web_url, "https://github.com") <> path

  defp config(key, default) do
    Application.get_env(:gradepush, GradePush.GitHub, []) |> Keyword.get(key, default)
  end

  defp repo_path(owner, repository), do: "/repos/#{segment(owner)}/#{segment(repository)}"
  defp segment(value), do: value |> to_string() |> URI.encode(&URI.char_unreserved?/1)
  defp path_segment(value), do: value |> String.split("/") |> Enum.map_join("/", &segment/1)
  defp id(value) when is_integer(value) and value > 0, do: Integer.to_string(value)

  defp id(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> Integer.to_string(number)
      _ -> raise ArgumentError, "invalid GitHub identifier"
    end
  end

  defp repository_id!(value) when is_integer(value) and value > 0, do: value

  defp repository_id!(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> raise ArgumentError, "invalid GitHub repository id"
    end
  end

  defp value(attributes, key),
    do: Map.get(attributes, key) || Map.get(attributes, Atom.to_string(key))

  defp rate_limited?(headers) do
    header(headers, "x-ratelimit-remaining") == "0" or header(headers, "retry-after") != nil
  end

  defp rate_limit_delay(headers) do
    case header(headers, "retry-after") do
      value when is_binary(value) ->
        parse_integer(value)

      _ ->
        case parse_integer(header(headers, "x-ratelimit-reset")) do
          nil -> nil
          reset -> max(reset - System.system_time(:second), 0)
        end
    end
  end

  defp header(headers, name) when is_list(headers) do
    Enum.find_value(headers, fn
      {key, value} when is_binary(key) -> if String.downcase(key) == name, do: to_string(value)
      _ -> nil
    end)
  end

  defp header(_headers, _name), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp safe_transport_reason(:timeout), do: :timeout
  defp safe_transport_reason(:nxdomain), do: :nxdomain
  defp safe_transport_reason(:econnrefused), do: :econnrefused
  defp safe_transport_reason(_), do: :request_failed
end
