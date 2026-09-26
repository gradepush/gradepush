defmodule GradePushWeb.Router do
  use GradePushWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug GradePushWeb.Plugs.Locale
    plug :fetch_live_flash
    plug :put_root_layout, html: {GradePushWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GradePushWeb do
    pipe_through :browser
    get "/", PageController, :home
  end

  scope "/", GradePushWeb do
    pipe_through :api
    get "/health", HealthController, :show
  end
end
