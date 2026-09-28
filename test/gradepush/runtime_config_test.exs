defmodule GradePush.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @variables ~w(PORT PHX_HOST PHX_SCHEME PHX_URL_PORT PHX_BIND_IP START_ENDPOINT TLS_CERTFILE TLS_KEYFILE SECRET_KEY_BASE CREDENTIAL_ENCRYPTION_KEY DB_HOST DB_USER DB_PASSWORD DATABASE_URL DATABASE_SSL DATABASE_SSL_CA_FILE)

  setup do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    System.put_env(%{
      "PORT" => "4104",
      "PHX_HOST" => "localhost",
      "PHX_URL_PORT" => "4104",
      "SECRET_KEY_BASE" => String.duplicate("s", 64),
      "CREDENTIAL_ENCRYPTION_KEY" => Base.encode64(String.duplicate("k", 32)),
      "DB_HOST" => "localhost",
      "DB_USER" => "gradepush",
      "DB_PASSWORD" => "test"
    })

    :ok
  end

  test "native development serves HTTPS only and generates HTTPS URLs on the selected port" do
    endpoint = endpoint_config(:dev)
    assert endpoint[:http] == false
    assert endpoint[:https][:port] == 4104
    assert endpoint[:https][:ip] == {127, 0, 0, 1}
    assert endpoint[:url][:scheme] == "https"
    assert endpoint[:url][:port] == 4104
    assert String.ends_with?(endpoint[:https][:certfile], "/priv/cert/localhost.pem")
  end

  test "release certificate paths select HTTPS instead of a plaintext listener" do
    System.put_env("TLS_CERTFILE", "/certs/localhost.pem")
    System.put_env("TLS_KEYFILE", "/certs/localhost-key.pem")
    endpoint = endpoint_config(:prod)
    assert endpoint[:http] == false
    assert endpoint[:https][:port] == 4104
    assert endpoint[:https][:certfile] == "/certs/localhost.pem"
    assert endpoint[:https][:keyfile] == "/certs/localhost-key.pem"
    assert endpoint[:url][:scheme] == "https"
  end

  test "release TLS configuration requires both certificate and key" do
    System.put_env("TLS_CERTFILE", "/certs/localhost.pem")

    assert_raise RuntimeError, "TLS_CERTFILE and TLS_KEYFILE must be configured together", fn ->
      endpoint_config(:prod)
    end
  end

  test "releases behind an HTTPS proxy retain the internal HTTP listener" do
    endpoint = endpoint_config(:prod)
    assert endpoint[:http][:port] == 4104
    assert endpoint[:url][:scheme] == "https"
    refute endpoint[:https]
  end

  test "database TLS uses Postgrex peer verification with system or supplied CAs" do
    assert repo_config()[:ssl] == false

    System.put_env("DATABASE_SSL", "true")
    assert repo_config()[:ssl] == true

    System.put_env("DATABASE_SSL_CA_FILE", "/certs/database-ca.pem")
    assert repo_config()[:ssl] == [cacertfile: "/certs/database-ca.pem"]

    System.put_env("DATABASE_SSL", "typo")

    assert_raise RuntimeError, "DATABASE_SSL must be true or false", fn ->
      repo_config()
    end
  end

  test "a native release can bind only to the reverse proxy's loopback interface" do
    System.put_env("PHX_BIND_IP", "127.0.0.1")
    assert endpoint_config(:prod)[:http][:ip] == {127, 0, 0, 1}

    System.put_env("PHX_BIND_IP", "invalid")

    assert_raise RuntimeError, "PHX_BIND_IP must be an IPv4 or IPv6 address", fn ->
      endpoint_config(:prod)
    end
  end

  defp repo_config do
    Config.Reader.read!("config/runtime.exs", env: :prod)
    |> get_in([:gradepush, GradePush.Repo])
  end

  defp endpoint_config(environment) do
    Config.Reader.read!("config/config.exs", env: environment)
    |> Config.Reader.merge(Config.Reader.read!("config/runtime.exs", env: environment))
    |> get_in([:gradepush, GradePushWeb.Endpoint])
  end
end
