defmodule GradePushWeb.LandingController do
  use GradePushWeb, :controller

  alias GradePush.Accounts

  def index(conn, _params) do
    destination =
      cond do
        GradePush.Demo.enabled?() and is_nil(conn.assigns[:current_user]) -> "/demo"
        conn.assigns[:preview?] -> "/classrooms"
        is_nil(Accounts.institution()) -> "/setup"
        is_nil(conn.assigns[:current_user]) -> "/auth/sign-in"
        true -> user_destination(conn.assigns.current_user)
      end

    redirect(conn, to: destination)
  end

  defp user_destination(user) do
    cond do
      Accounts.teacher?(user) -> "/classrooms"
      Accounts.admin?(user) -> "/admin/institution"
      Accounts.operator?(user) -> "/admin/platform"
      true -> "/student/classrooms"
    end
  end
end
