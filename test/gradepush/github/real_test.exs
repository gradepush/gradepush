defmodule GradePush.GitHub.RealTest do
  use ExUnit.Case, async: false

  alias GradePush.GitHub.Actions
  alias GradePush.GitHub.Real

  setup do
    previous = Application.get_env(:gradepush, GradePush.GitHub)

    Application.put_env(:gradepush, GradePush.GitHub,
      adapter: Real,
      api_url: "https://api.github.com",
      web_url: "https://github.com",
      api_version: "2026-03-10",
      http_client: GradePush.GitHub.RealTest.HTTPClient
    )

    Process.put(:gradepush_github_test_pid, self())
    Process.put(:gradepush_github_test_responses, [])

    on_exit(fn ->
      Process.delete(:gradepush_github_test_pid)
      Process.delete(:gradepush_github_test_responses)

      if previous do
        Application.put_env(:gradepush, GradePush.GitHub, previous)
      else
        Application.delete_env(:gradepush, GradePush.GitHub)
      end
    end)

    :ok
  end

  test "manifest conversion sends the code in the escaped path and does not construct an app secret" do
    queue_response(response(201, %{"id" => 42, "client_id" => "Iv1.test"}))

    assert {:ok, %{"id" => 42}} = Real.convert_manifest("code/with+reserved")

    assert_received {:github_request, :post, url, headers, nil}
    assert url == "https://api.github.com/app-manifests/code%2Fwith%2Breserved/conversions"

    assert Enum.any?(headers, fn {key, value} ->
             key == "x-github-api-version" and value == "2026-03-10"
           end)
  end

  test "repository invitation revocation paginates and uses scoped DELETE endpoints" do
    invitations = for id <- 1..100, do: %{"id" => id, "invitee" => %{"id" => id + 1000}}
    queue_response(response(200, invitations))
    queue_response(response(200, [%{"id" => 101, "invitee" => %{"id" => 1101}}]))
    assert {:ok, all} = Real.list_repository_invitations("repo-token", "org", "repo")
    assert length(all) == 101

    assert_received {:github_request, :get,
                     "https://api.github.com/repos/org/repo/invitations?per_page=100&page=1", _,
                     nil}

    assert_received {:github_request, :get,
                     "https://api.github.com/repos/org/repo/invitations?per_page=100&page=2", _,
                     nil}

    queue_response(response(204, nil))
    assert {:ok, _} = Real.delete_repository_invitation("repo-token", "org", "repo", 101)

    assert_received {:github_request, :delete,
                     "https://api.github.com/repos/org/repo/invitations/101", headers, nil}

    assert {"authorization", "Bearer repo-token"} in headers

    queue_response(response(204, nil))
    assert {:ok, _} = Real.remove_collaborator("repo-token", "org", "repo", "current-login")

    assert_received {:github_request, :delete,
                     "https://api.github.com/repos/org/repo/collaborators/current-login", _, nil}

    queue_response(response(403, %{"message" => "Forbidden"}))
    assert {:error, _} = Real.remove_collaborator("repo-token", "org", "repo", "current-login")
  end

  test "OAuth exchange keeps credentials in the POST body" do
    queue_response(response(200, %{"access_token" => "user-token"}))

    assert {:ok, %{"access_token" => "user-token"}} =
             Real.exchange_user_code("one-time-code", "client-id", "client-secret")

    assert_received {:github_request, :post, "https://github.com/login/oauth/access_token",
                     headers, body}

    assert Jason.decode!(body) == %{
             "client_id" => "client-id",
             "client_secret" => "client-secret",
             "code" => "one-time-code"
           }

    refute Enum.any?(headers, fn {_key, value} -> String.contains?(value, "client-secret") end)
  end

  test "workflow results and jobs are fetched for the exact attempt" do
    queue_response(response(200, %{"id" => 90, "run_attempt" => 2}))
    queue_response(response(200, %{"jobs" => [%{"id" => 91}]}))
    assert {:ok, %{"run_attempt" => 2}} = Real.get_workflow_run("token", "school", "lab", 90, 2)
    assert {:ok, [%{"id" => 91}]} = Real.list_workflow_jobs("token", "school", "lab", 90, 2)

    assert_received {:github_request, :get,
                     "https://api.github.com/repos/school/lab/actions/runs/90/attempts/2", _, nil}

    assert_received {:github_request, :get,
                     "https://api.github.com/repos/school/lab/actions/runs/90/attempts/2/jobs?per_page=100",
                     _, nil}
  end

  test "user installation lookup paginates the installations wrapper and finds the requested ID" do
    first_page = Enum.map(1..100, &%{"id" => &1, "account" => %{"login" => "org-#{&1}"}})
    second_page = [%{"id" => 101, "account" => %{"login" => "final-org"}}]
    queue_response(response(200, %{"total_count" => 101, "installations" => first_page}))
    queue_response(response(200, %{"total_count" => 101, "installations" => second_page}))

    assert {:ok, %{"id" => 101, "account" => %{"login" => "final-org"}}} =
             Real.get_user_installation("user-token", 101)

    assert_received {:github_request, :get,
                     "https://api.github.com/user/installations?per_page=100&page=1", _, nil}

    assert_received {:github_request, :get,
                     "https://api.github.com/user/installations?per_page=100&page=2", _, nil}
  end

  test "organization membership and stable-ID user lookup use documented endpoints" do
    queue_response(response(200, %{"state" => "active", "role" => "admin"}))

    assert {:ok, %{"state" => "active", "role" => "admin"}} =
             Real.get_user_organization_membership("user-token", "montjoie-school")

    assert_received {:github_request, :get,
                     "https://api.github.com/user/memberships/orgs/montjoie-school", _, nil}

    queue_response(response(200, %{"id" => 804, "login" => "renamed-student"}))

    assert {:ok, %{"id" => 804, "login" => "renamed-student"}} =
             Real.get_user_by_id("installation-token", 804)

    assert_received {:github_request, :get, "https://api.github.com/user/804", _, nil}
  end

  test "installation token request carries repository scoping and a valid short-lived App JWT" do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])
    public_key = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}
    queue_response(response(201, %{"token" => "installation-token"}))

    assert {:ok, %{"token" => "installation-token"}} =
             Real.installation_token(%{client_id: "Iv1.test", private_key: pem}, 77,
               repository_ids: [987]
             )

    assert_received {:github_request, :post,
                     "https://api.github.com/app/installations/77/access_tokens", headers, body}

    assert Jason.decode!(body) == %{"repository_ids" => [987]}

    assert {"authorization", "Bearer " <> jwt} =
             Enum.find(headers, &(elem(&1, 0) == "authorization"))

    [header, claims, signature] = String.split(jwt, ".")

    assert Jason.decode!(Base.url_decode64!(header, padding: false)) == %{
             "alg" => "RS256",
             "typ" => "JWT"
           }

    assert %{"iss" => "Iv1.test", "iat" => iat, "exp" => exp} =
             Jason.decode!(Base.url_decode64!(claims, padding: false))

    assert exp - iat == 9 * 60

    assert :public_key.verify(
             header <> "." <> claims,
             :sha256,
             Base.url_decode64!(signature, padding: false),
             public_key
           )
  end

  test "repository creation refuses to adopt a pre-existing name" do
    queue_response(response(200, %{"id" => 1, "name" => "assignment-1"}))

    assert {:error, :repository_name_taken} =
             Real.create_repository("installation-token", "school", %{
               repository_name: "assignment-1",
               visibility: "private"
             })

    assert_received {:github_request, :get, "https://api.github.com/repos/school/assignment-1",
                     _headers, nil}

    refute_received {:github_request, :post, _, _, _}
  end

  test "empty repository creation is initialized for workflow installation" do
    queue_response(response(404, %{}))

    queue_response(
      response(201, %{
        "id" => 22,
        "name" => "assignment-1",
        "full_name" => "school/assignment-1",
        "html_url" => "https://github.com/school/assignment-1",
        "owner" => %{"login" => "school"}
      })
    )

    assert {:ok, %{"id" => 22}} =
             Real.create_repository("installation-token", "school", %{
               repository_name: "assignment-1",
               visibility: "private"
             })

    assert_received {:github_request, :get, _, _, nil}

    assert_received {:github_request, :post, "https://api.github.com/orgs/school/repos", _headers,
                     body}

    assert Jason.decode!(body)["auto_init"]
  end

  test "template workflow setup recovers an identical existing file after a retry" do
    tests = [
      %{
        id: 4,
        name: "smoke",
        type: "command",
        command: "echo ready",
        points: 1,
        timeout_seconds: 60
      }
    ]

    {:ok, content} = Actions.generate_workflow(tests)
    queue_response(response(200, %{"sha" => "blob-sha", "content" => Base.encode64(content)}))
    queue_response(response(200, %{"id" => 99}))

    assert {:ok, %{workflow_id: 99, workflow_file_sha: "blob-sha", workflow_path: path}} =
             Real.install_autograding_workflow(
               "installation-token",
               "school",
               "assignment-1",
               tests
             )

    assert path == ".github/workflows/gradepush.yml"

    assert_received {:github_request, :get,
                     "https://api.github.com/repos/school/assignment-1/contents/.github/workflows/gradepush.yml?ref=HEAD",
                     _, nil}

    assert_received {:github_request, :get,
                     "https://api.github.com/repos/school/assignment-1/actions/workflows/gradepush.yml",
                     _, nil}

    refute_received {:github_request, :put, _, _, _}
  end

  test "workflow creation reads the blob SHA from the Contents API write response" do
    tests = [
      %{
        id: 4,
        name: "smoke",
        type: "command",
        command: "echo ready",
        points: 1,
        timeout_seconds: 60
      }
    ]

    {:ok, content} = Actions.generate_workflow(tests)
    queue_response(response(404, %{}))

    queue_response(
      response(201, %{
        "content" => %{"sha" => "blob-sha"},
        "commit" => %{"sha" => "commit-sha"}
      })
    )

    queue_response(response(200, %{"id" => 99}))

    assert {:ok,
            %{
              workflow_id: 99,
              workflow_file_sha: "blob-sha",
              workflow_commit_sha: "commit-sha"
            }} =
             Real.install_autograding_workflow(
               "installation-token",
               "school",
               "assignment-1",
               tests
             )

    assert_received {:github_request, :put,
                     "https://api.github.com/repos/school/assignment-1/contents/.github/workflows/gradepush.yml",
                     _, body}

    assert Jason.decode!(body)["content"] == Base.encode64(content)
  end

  test "an unrelated existing workflow file is never overwritten" do
    queue_response(
      response(200, %{"sha" => "other", "content" => Base.encode64("name: teacher workflow\n")})
    )

    tests = [
      %{
        id: 4,
        name: "smoke",
        type: "command",
        command: "echo ready",
        points: 1,
        timeout_seconds: 60
      }
    ]

    assert {:error, :workflow_already_exists} =
             Real.install_autograding_workflow(
               "installation-token",
               "school",
               "assignment-1",
               tests
             )

    refute_received {:github_request, :put, _, _, _}

    assert_received {:github_request, :get,
                     "https://api.github.com/repos/school/assignment-1/contents/.github/workflows/gradepush.yml?ref=HEAD",
                     _, nil}
  end

  test "rate-limit responses preserve a retry delay without returning GitHub response bodies" do
    queue_response(
      {:ok,
       %{
         status: 403,
         headers: [{"x-ratelimit-remaining", "0"}, {"retry-after", "12"}],
         body: "secret response"
       }}
    )

    assert {:error, {:rate_limited, 12}} = Real.get_user("user-token")
  end

  defp queue_response(response),
    do:
      Process.put(
        :gradepush_github_test_responses,
        Process.get(:gradepush_github_test_responses) ++ [response]
      )

  defp response(status, payload),
    do: {:ok, %{status: status, headers: [], body: Jason.encode!(payload)}}
end

defmodule GradePush.GitHub.RealTest.HTTPClient do
  def request(method, url, headers, body) do
    send(Process.get(:gradepush_github_test_pid), {:github_request, method, url, headers, body})

    case Process.get(:gradepush_github_test_responses) do
      [response | rest] ->
        Process.put(:gradepush_github_test_responses, rest)
        response

      [] ->
        {:error, :unexpected_request}
    end
  end
end
