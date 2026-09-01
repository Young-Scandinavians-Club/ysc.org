defmodule YscWeb.PhoenixLiveDashboardUpgradeTest do
  @moduledoc """
  Guards the phoenix_live_dashboard 0.9.0 → 0.9.1 upgrade.

  0.9.1 is a patch: Ecto Stats skips repos that cannot resolve an extras
  module (dynamic names / pids from `Ecto.Repo.all_running/0` that do not
  answer `__adapter__/0`). Router, RequestLogger, and `menu_link/2` are
  unchanged. We mount the dashboard at `/admin/dashboard` with auto-discovered
  `Ysc.Repo` and `ecto_psql_extras`.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Phoenix.LiveDashboard.EctoStatsPage
  alias Phoenix.LiveDashboard.RequestLogger
  alias Phoenix.LiveDashboard.Router
  alias Ysc.Repo

  @ecto_stats_page Path.expand(
                     "../../deps/phoenix_live_dashboard/lib/phoenix/live_dashboard/pages/ecto_stats_page.ex",
                     __DIR__
                   )

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "0.9.1 Hex lock and public APIs" do
    test "locks the Hex package to 0.9.1" do
      assert to_string(Application.spec(:phoenix_live_dashboard, :vsn)) ==
               "0.9.1"
    end

    test "router, request logger, and ecto stats callbacks we use still exist" do
      assert {:module, Router} = Code.ensure_loaded(Router)
      assert {:module, RequestLogger} = Code.ensure_loaded(RequestLogger)
      assert {:module, EctoStatsPage} = Code.ensure_loaded(EctoStatsPage)
      assert macro_exported?(Router, :live_dashboard, 1)
      assert macro_exported?(Router, :live_dashboard, 2)
      assert function_exported?(RequestLogger, :init, 1)
      assert function_exported?(RequestLogger, :call, 2)
      assert function_exported?(EctoStatsPage, :menu_link, 2)
      assert function_exported?(EctoStatsPage, :init, 1)
    end

    test "menu_link still enables Ecto Stats when extras are loaded" do
      assert {:ok, "Ecto Stats"} =
               EctoStatsPage.menu_link(%{repos: :auto_discover}, %{})
    end
  end

  describe "0.9.1 Ecto extras skip" do
    test "catches adapter lookup failures for names that are not repo modules" do
      source = File.read!(@ecto_stats_page)

      assert source =~ "defp adapter_for(node, repo)"
      assert source =~ "catch"
      assert source =~ "for repo <- repos, extra_available?(node, repo)"
      assert source =~ "defp extra_available?(_node, _repo_pid), do: false"
    end

    test "Ysc.Repo still resolves to Postgres extras" do
      assert Ysc.Repo in Ecto.Repo.all_running()

      assert :erpc.call(node(), Repo, :__adapter__, []) ==
               Ecto.Adapters.Postgres

      assert Code.ensure_loaded?(EctoPSQLExtras)
    end

    test "adapter lookup on a non-repo atom is catchable so extras can skip it" do
      caught =
        try do
          :erpc.call(node(), :not_a_repo_module, :__adapter__, [])
        catch
          _, _ -> :caught
        end

      assert caught == :caught
    end
  end

  describe "admin LiveDashboard pages" do
    setup [:create_admin]

    setup do
      prev = Application.get_env(:phoenix_live_view, :test_warnings)

      Application.put_env(:phoenix_live_view, :test_warnings,
        missing_form_id: :ignore
      )

      on_exit(fn ->
        if prev do
          Application.put_env(:phoenix_live_view, :test_warnings, prev)
        else
          Application.delete_env(:phoenix_live_view, :test_warnings)
        end
      end)

      :ok
    end

    test "home page mounts for a full admin", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/dashboard/home")

      assert has_element?(view, ".menu-item", "Home")
      assert has_element?(view, ".menu-item", "Ecto Stats")
    end

    test "ecto stats page still lists the named Ysc.Repo", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/dashboard/ecto_stats")

      assert has_element?(view, ".menu-item.active", "Ecto Stats")
      assert has_element?(view, ".nav-item", "Ysc.Repo")
      refute has_element?(view, "*", "no_ecto_repos_available")
    end
  end
end
