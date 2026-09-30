defmodule GradePushWeb.Router do
  use GradePushWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug GradePushWeb.Auth, :fetch_current_user
    plug GradePushWeb.Plugs.Locale
    plug :fetch_live_flash
    plug :put_root_layout, html: {GradePushWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug GradePushWeb.Plugs.BrowserSecurity
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GradePushWeb do
    pipe_through :browser
    get "/", LandingController, :index
    get "/auth/github", AuthController, :new
    get "/auth/github/callback", AuthController, :callback
    delete "/auth/logout", AuthController, :delete
    post "/demo/sign-in", DemoController, :create
    get "/setup/github/manifest/callback", SetupController, :manifest_callback
    get "/setup/github/auth/callback", SetupController, :auth_callback
    get "/github/organizations/connect", OrganizationController, :new
    get "/github/organizations/callback", OrganizationController, :callback
    get "/classrooms/:slug/assignments/:assignment/export.csv", ExportController, :submissions

    live_session :public do
      live "/demo", DemoLive, :index
      live "/setup", SetupLive, :index
      live "/auth/sign-in", SignInLive, :index
    end

    live_session :cli_access, on_mount: [{GradePushWeb.Auth, :require_authenticated_user}] do
      live "/cli/authorize", CLIAuthorizationLive, :authorize
    end

    live_session :teaching, on_mount: [{GradePushWeb.Auth, :require_teacher}] do
      live "/classrooms", TeacherLive, :index
      live "/teacher/settings", TeacherLive, :settings
      live "/signed-out", TeacherLive, :signed_out
      live "/classrooms/:slug", TeacherLive, :show
      live "/classrooms/:slug/assignments/new", TeacherLive, :new_assignment
      live "/classrooms/:slug/assignments/:assignment/edit", TeacherLive, :edit_assignment
      live "/classrooms/:slug/assignments/:assignment", TeacherLive, :assignment
    end

    live_session :administration, on_mount: [{GradePushWeb.Auth, :require_authenticated_user}] do
      live "/admin/institution", AdminLive, :institution
      live "/admin/platform", AdminLive, :platform
    end

    live_session :learning, on_mount: [{GradePushWeb.Auth, :require_authenticated_user}] do
      live "/student/classrooms", StudentLive, :index
      live "/student/assignments", StudentLive, :schedule
      live "/student/classrooms/:slug", StudentLive, :show
      live "/student/classrooms/:slug/assignments/:assignment", StudentLive, :assignment
      live "/join/:kind/:token", InvitationLive, :show
    end
  end

  scope "/", GradePushWeb do
    pipe_through :api
    get "/health", HealthController, :show
    get "/health/ready", HealthController, :ready
    post "/webhooks/github", GitHubWebhookController, :create
    post "/api/v1/cli/device", CLIController, :device
    post "/api/v1/cli/token", CLIController, :token
    get "/api/v1/cli/session", CLIController, :session
    delete "/api/v1/cli/session", CLIController, :delete_session
    get "/api/v1/cli/repositories", CLIController, :repositories
  end
end
