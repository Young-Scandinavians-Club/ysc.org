defmodule Ysc.SettingsCacheFaultTest do
  @moduledoc """
  Covers `Ysc.Settings` fallbacks when Cachex returns `{:error, :no_cache}` (e.g. after the
  Cachex supervisor child is stopped). `Supervisor.terminate_child/2` does not auto-restart
  the child in this setup, so tests use `on_exit/1` to call `Supervisor.restart_child/2`.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Settings
  alias Ysc.SiteSettings.SiteSetting

  @moduletag skip_settings_setup: true

  setup do
    Repo.delete_all(SiteSetting)
    Settings.clear_cache()
    :ok
  end

  describe "when Cachex is temporarily unavailable" do
    setup do
      on_exit(&restore_cachex_if_stopped/0)
      :ok
    end

    test "settings/0, get_setting/1, and get_setting_safe/1 fall back to the database" do
      name = "cache_fault_#{System.unique_integer([:positive])}"

      %SiteSetting{name: name, value: "from_db", group: "g"}
      |> Repo.insert!()

      Settings.clear_cache()

      assert :ok = Supervisor.terminate_child(Ysc.Supervisor, Cachex)

      assert [%SiteSetting{} = row] = Settings.settings()
      assert row.name == name
      assert Settings.get_setting(name) == "from_db"
      assert Settings.get_setting_safe(name) == "from_db"

      assert {:ok, _} = Supervisor.restart_child(Ysc.Supervisor, Cachex)
    end

    test "clear_cache/0 tolerates Cachex.keys/1 errors" do
      name = "clear_keys_#{System.unique_integer([:positive])}"
      %SiteSetting{name: name, value: "v", group: "g"} |> Repo.insert!()
      Settings.clear_cache()

      assert :ok = Supervisor.terminate_child(Ysc.Supervisor, Cachex)

      assert :ok = Settings.clear_cache()

      assert {:ok, _} = Supervisor.restart_child(Ysc.Supervisor, Cachex)

      assert Settings.get_setting(name) == "v"
    end
  end

  defp restore_cachex_if_stopped do
    if Process.whereis(:ysc_cache) == nil do
      assert {:ok, _} = Supervisor.restart_child(Ysc.Supervisor, Cachex)
    end

    :ok
  end
end
