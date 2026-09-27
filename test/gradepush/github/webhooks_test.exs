defmodule GradePush.GitHub.WebhooksTest do
  use ExUnit.Case, async: true

  alias GradePush.GitHub.Webhooks

  test "verifies GitHub's documented SHA-256 HMAC example against exact request bytes" do
    signature = "sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17"

    assert :ok =
             Webhooks.verify_signature("Hello, World!", signature, "It's a Secret to Everybody")

    assert {:error, :invalid_signature} =
             Webhooks.verify_signature("Hello, World! ", signature, "It's a Secret to Everybody")
  end

  test "rejects malformed and non-SHA-256 signatures" do
    assert {:error, :invalid_signature} =
             Webhooks.verify_signature("payload", "sha1=bad", "secret")

    assert {:error, :invalid_signature} =
             Webhooks.verify_signature("payload", "sha256=00", "secret")

    assert {:error, :invalid_signature} =
             Webhooks.verify_signature("payload", "sha256=" <> String.duplicate("0", 64), "")
  end
end

defmodule GradePush.GitHub.WebhooksPersistenceTest do
  use GradePush.DataCase, async: false
  use Oban.Testing, repo: GradePush.Repo

  import Ecto.Query

  alias GradePush.Crypto
  alias GradePush.GitHub.{Delivery, Webhooks}
  alias GradePush.Installation.GitHubApp

  setup do
    insert_github_app()
    :ok
  end

  test "authenticates exact webhook bytes and atomically deduplicates delivery plus job" do
    body = push_payload()
    headers = signed_headers("delivery-1", "push", body)

    assert {:ok, :accepted} = Webhooks.receive(body, headers)

    assert %Delivery{id: delivery_id, status: "pending", payload: normalized} =
             Repo.get_by!(Delivery, delivery_id: "delivery-1")

    assert normalized["commit_sha"] == String.duplicate("a", 40)
    assert normalized["sender_type"] == "Bot"
    assert normalized["sender_login"] == "gradepush-test[bot]"

    assert Map.keys(normalized) |> Enum.sort() ==
             ~w(branch commit_sha owner_login repository_id repository_name sender_login sender_type)

    assert [%Oban.Job{args: %{"delivery_id" => ^delivery_id}}] =
             all_enqueued(queue: :github, worker: GradePush.Workers.ProcessGitHubDelivery)

    assert {:ok, :duplicate} = Webhooks.receive(body, headers)

    changed_body = String.replace(body, "refs/heads/main", "refs/heads/other")

    assert {:error, :delivery_payload_conflict} =
             Webhooks.receive(changed_body, signed_headers("delivery-1", "push", changed_body))

    assert Repo.aggregate(from(d in Delivery, where: d.delivery_id == "delivery-1"), :count) == 1

    assert length(all_enqueued(queue: :github, worker: GradePush.Workers.ProcessGitHubDelivery)) ==
             1
  end

  test "stores ping deliveries as ignored without enqueueing background work" do
    body = ~s({"zen":"Keep it logically awesome."})

    assert {:ok, :ignored} = Webhooks.receive(body, signed_headers("ping-1", "ping", body))
    assert %Delivery{status: "ignored"} = Repo.get_by!(Delivery, delivery_id: "ping-1")
    assert all_enqueued(queue: :github, worker: GradePush.Workers.ProcessGitHubDelivery) == []
  end

  test "an authenticated redelivery retries a failed event without changing its observed time" do
    body = push_payload()
    headers = signed_headers("retry-delivery", "push", body)
    assert {:ok, :accepted} = Webhooks.receive(body, headers)
    delivery = Repo.get_by!(Delivery, delivery_id: "retry-delivery")
    Repo.delete_all(Oban.Job)

    delivery
    |> Delivery.changeset(%{status: "failed", last_error: "github_unavailable"})
    |> Repo.update!()

    assert {:error, :invalid_signature} = Webhooks.receive(body <> " ", headers)
    assert Repo.get!(Delivery, delivery.id).status == "failed"
    assert {:ok, :accepted} = Webhooks.receive(body, headers)
    restored = Repo.get!(Delivery, delivery.id)
    assert restored.status == "pending"
    assert restored.received_at == delivery.received_at
    assert restored.last_error == nil
    assert {:ok, :duplicate} = Webhooks.receive(body, headers)
    assert [%Oban.Job{args: %{"delivery_id" => id}}] = all_enqueued(queue: :github)
    assert id == delivery.id
  end

  defp insert_github_app do
    {:ok, client_secret} = Crypto.encrypt("client-secret", "github_app.client_secret")
    {:ok, private_key} = Crypto.encrypt("unused-private-key", "github_app.private_key")
    {:ok, webhook_secret} = Crypto.encrypt("test-webhook-secret", "github_app.webhook_secret")

    %GitHubApp{}
    |> GitHubApp.changeset(%{
      app_id: 1,
      client_id: "Iv1.test",
      client_secret_encrypted: client_secret,
      private_key_encrypted: private_key,
      webhook_secret_encrypted: webhook_secret,
      slug: "gradepush-test",
      html_url: "https://github.com/apps/gradepush-test"
    })
    |> Repo.insert!()
  end

  defp push_payload do
    Jason.encode!(%{
      ref: "refs/heads/main",
      after: String.duplicate("a", 40),
      deleted: false,
      repository: %{
        id: 99,
        name: "assignment-1",
        owner: %{login: "school"}
      },
      sender: %{type: "Bot", login: "gradepush-test[bot]"}
    })
  end

  defp signed_headers(id, event, body) do
    signature =
      :crypto.mac(:hmac, :sha256, "test-webhook-secret", body) |> Base.encode16(case: :lower)

    [
      {"x-github-delivery", id},
      {"x-github-event", event},
      {"x-hub-signature-256", "sha256=" <> signature}
    ]
  end
end
