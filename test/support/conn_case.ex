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
end
