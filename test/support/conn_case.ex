defmodule GradePushWeb.ConnCase do
  @moduledoc "Connection tests with a sandboxed database and verified routes."

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint GradePushWeb.Endpoint

      use GradePushWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import GradePushWeb.ConnCase
    end
  end

  setup tags do
    GradePush.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def log_in_user(conn, user) do
    {:ok, token} = GradePush.Accounts.create_session(user)
    Phoenix.ConnTest.init_test_session(conn, %{"user_token" => token, "ui_preview" => false})
  end

  def eventually(check, attempts \\ 50) do
    cond do
      check.() ->
        true

      attempts <= 1 ->
        false

      true ->
        Process.sleep(10)
        eventually(check, attempts - 1)
    end
  end
end
