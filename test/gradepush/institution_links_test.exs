defmodule GradePush.InstitutionLinksTest do
  use GradePush.DataCase, async: true, group: :institution

  import GradePush.AccountsFixtures
  alias GradePush.Accounts

  test "only institution administrators can save links, with an audit entry" do
    %{user: admin} = bootstrap_fixture()
    teacher = user_fixture()
    teacher_membership_fixture(teacher)

    for actor <- [nil, teacher, user_fixture()] do
      assert {:error, :unauthorized} =
               Accounts.update_footer_links(actor, %{privacy_url: "https://example.org/privacy"})
    end

    assert {:ok, links} =
             Accounts.update_footer_links(admin, %{
               support_url: " mailto:help@example.org ",
               privacy_url: "https://example.org/privacy",
               accessibility_url: "https://example.org/accessibility",
               terms_url: "https://example.org/terms",
               name: "Ignored name"
             })

    assert links.support_url == "mailto:help@example.org"
    assert Accounts.footer_links() == links
    refute Accounts.institution().name == "Ignored name"
    assert {:ok, events} = Accounts.list_audit(admin, :institution)
    assert Enum.count(events, &(&1.action == "institution.footer_updated")) == 1

    assert {:ok, cleared} = Accounts.update_footer_links(admin, %{support_url: "  "})
    assert is_nil(cleared.support_url)
    assert cleared.privacy_url == links.privacy_url
  end

  test "invalid addresses cannot be saved or generate an audit event" do
    %{user: admin} = bootstrap_fixture()

    for url <- [
          "javascript:alert(1)",
          "data:text/html,test",
          "//example.org",
          "/privacy",
          "http://example.org",
          "https://",
          "https://user:pass@example.org",
          "https://example.org/\\evil",
          "https://example.org/a\nb",
          "mailto:help@example.org?body=test",
          "mailto:help%0a@example.org",
          "https://example.org/" <> String.duplicate("a", 2_048)
        ] do
      assert {:error, changeset} = Accounts.update_footer_links(admin, %{support_url: url})
      assert Keyword.has_key?(changeset.errors, :support_url)
    end

    assert {:error, changeset} =
             Accounts.update_footer_links(admin, %{privacy_url: "mailto:help@example.org"})

    assert Keyword.has_key?(changeset.errors, :privacy_url)
    assert is_nil(Accounts.footer_links().support_url)
    assert {:ok, events} = Accounts.list_audit(admin, :institution)
    refute Enum.any?(events, &(&1.action == "institution.footer_updated"))
  end
end
