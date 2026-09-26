defmodule GradePushWeb.PageController do
  use GradePushWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
