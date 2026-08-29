defmodule YscWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used for tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also import other functionality to make it easier
  to build common data structures and query the application.

  Finally, if your test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use YscWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.

  ## Options

    * `:mox_global_first` — when `true`, enables Mox global mode **before** default
      HTTP/Stripe stubs run so LiveViews and spawned tasks can call mocks. Only the
      process that enables global mode may define stubs in shared mode. Resets to
      private mode when the test exits.

      Pass together with `async: false`, per Mox requirements.

      Example:

          use YscWeb.ConnCase, async: false, mox_global_first: true

  """

  use ExUnit.CaseTemplate

  using(opts) do
    exunit_opts = Keyword.take(opts, [:async])
    mox_global_first_flag = Keyword.get(opts, :mox_global_first, false)

    quote do
      @conn_case_opts unquote(Macro.escape(opts))

      # The default endpoint for testing
      @endpoint YscWeb.Endpoint

      use ExUnit.Case, unquote(Macro.escape(exunit_opts))

      use YscWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import YscWeb.ConnCase
      import Ysc.EmailValidatorTestHelper

      def post_token_login(conn, path, params)
          when is_binary(path) and is_map(params) do
        {conn, csrf} = YscWeb.ConnCase.fetch_conn_csrf(conn)
        post(conn, path, Map.put(params, "_csrf_token", csrf))
      end

      import Ysc.Test.Invoke
      import Mox

      setup tags do
        Ysc.Test.EnvHelper.reset_environment!()

        if unquote(mox_global_first_flag) do
          Mox.set_mox_global()
          on_exit(fn -> Mox.set_mox_private() end)
        end

        Ysc.DataCase.setup_sandbox(tags)

        if !tags[:skip_settings_setup] do
          if Ysc.Repo.aggregate(Ysc.SiteSettings.SiteSetting, :count) == 0 do
            Ysc.Settings.ensure_settings_exist()
          end
        end

        Ysc.DataCase.invalidate_shared_caches()

        if tags[:process_caches] do
          Application.put_env(:ysc, :process_caches_enabled, true)

          on_exit(fn ->
            Application.put_env(:ysc, :process_caches_enabled, false)
          end)
        end

        Ysc.DataCase.stub_default_external_mocks()

        secret_key_base =
          Application.get_env(:ysc, YscWeb.Endpoint)[:secret_key_base] ||
            String.duplicate("test", 16)

        conn =
          Phoenix.ConnTest.build_conn()
          |> Map.put(:secret_key_base, secret_key_base)

        {:ok, conn: conn}
      end
    end
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = Ysc.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user) do
    token = Ysc.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc """
  Account setup URL including the signed `setup_token` required for email verification.
  """
  def account_setup_path(user, extra_params \\ %{}) do
    YscWeb.AccountSetupAccess.setup_path(user.id, extra_params)
  end

  @doc """
  Returns `{conn, csrf_token}` by running session + CSRF plugs (no page render).

  Use for controller POST tests instead of `get(conn, ~p"/")` + `fetch_conn_csrf_from_html/1`.
  The token is valid for any pipeline that uses `:protect_from_forgery` on the same session.
  """
  def fetch_conn_csrf(conn) do
    conn =
      conn
      |> ensure_test_session()
      |> Plug.Conn.fetch_session()
      |> Plug.CSRFProtection.call(Plug.CSRFProtection.init([]))

    {conn, Plug.CSRFProtection.get_csrf_token()}
  end

  defp ensure_test_session(%{private: %{plug_session_fetch: :done}} = conn),
    do: conn

  defp ensure_test_session(conn) do
    Phoenix.ConnTest.init_test_session(conn, %{})
  end

  @doc """
  Reads the CSRF token from a rendered HTML page's `<meta name="csrf-token">` tag.

  Expects `conn` to be the connection returned from a successful `get/2` that ran
  through the browser pipeline (session + CSRF).
  """
  def fetch_conn_csrf_from_html(conn) do
    html = Phoenix.ConnTest.html_response(conn, 200)

    token =
      case Regex.run(~r/<meta\s+name="csrf-token"\s+content="([^"]+)"/, html) do
        [_, t] ->
          t

        nil ->
          case Regex.run(
                 ~r/<meta\s+content="([^"]+)"\s+name="csrf-token"/,
                 html
               ) do
            [_, t] ->
              t

            nil ->
              raise ArgumentError, "no csrf-token meta tag in HTML response"
          end
      end

    {conn, token}
  end

  @doc """
  Asserts `conn` rendered the browser→mobile-app handoff page and returns the
  one-time `code` from its `ysc-admin://auth-callback?code=…` deep link.

  The handoff is an HTML page, not a 302: Chrome for Android silently drops a
  redirect to a private-use scheme (see `YscWeb.UserAuth.send_mobile_app_handoff/3`).
  """
  def assert_mobile_app_handoff(conn) do
    html = Phoenix.ConnTest.html_response(conn, 200)

    href =
      html
      |> Floki.parse_document!()
      |> Floki.attribute("a#open-app", "href")
      |> List.first()

    unless href do
      raise ArgumentError,
            "expected an `a#open-app` deep link in the handoff HTML:\n#{html}"
    end

    %{"code" => code} = URI.decode_query(URI.parse(href).query || "")
    code
  end
end
