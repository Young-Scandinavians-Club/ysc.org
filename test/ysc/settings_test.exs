defmodule Ysc.SettingsTest do
  use Ysc.DataCase, async: false
  alias Ysc.Settings
  alias Ysc.SiteSettings.SiteSetting

  @moduletag skip_settings_setup: true

  setup do
    # Clear out any existing settings and cache before each test
    Repo.delete_all(SiteSetting)
    Settings.clear_cache()
    :ok
  end

  describe "settings/0" do
    test "returns all settings ordered by id desc" do
      # Clear cache before test to ensure fresh state
      Settings.clear_cache()

      setting1 =
        %SiteSetting{name: "setting1", value: "value1"} |> Repo.insert!()

      # Add a small delay to ensure setting2 gets a later ULID
      Process.sleep(1)

      setting2 =
        %SiteSetting{name: "setting2", value: "value2"} |> Repo.insert!()

      # Clear cache again to force fresh query from DB
      Settings.clear_cache()

      settings = Settings.settings()
      assert length(settings) == 2

      # Since setting2 was created after setting1, its ID should be "greater" (newer ULID)
      # and thus come first when ordered by desc
      # Check that both settings are present and setting2 comes first
      assert Enum.map(settings, & &1.id) == [setting2.id, setting1.id]
    end

    test "uses cache when available" do
      # Clear cache before test to ensure clean state
      Settings.clear_cache()

      setting = %SiteSetting{name: "test", value: "test"} |> Repo.insert!()

      # First call populates cache
      [cached_setting] = Settings.settings()
      assert cached_setting.id == setting.id

      # Delete from DB but should still return from cache
      Repo.delete!(setting)
      assert [^cached_setting] = Settings.settings()
    end
  end

  describe "get_setting/1" do
    test "returns setting value" do
      %SiteSetting{name: "test_setting", value: "test_value"} |> Repo.insert!()
      assert Settings.get_setting("test_setting") == "test_value"
    end

    test "raises if setting not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Settings.get_setting("nonexistent")
      end
    end

    test "uses cache when available" do
      setting = %SiteSetting{name: "cached", value: "old"} |> Repo.insert!()

      # First call populates cache
      assert Settings.get_setting("cached") == "old"

      # Update DB directly (bypassing Settings.update_setting which would update cache)
      setting
      |> Ecto.Changeset.change(value: "new")
      |> Repo.update!()

      # Should still return cached value since we didn't use Settings.update_setting
      assert Settings.get_setting("cached") == "old"
    end
  end

  describe "update_setting/2" do
    test "updates setting value" do
      setting = %SiteSetting{name: "test", value: "old"} |> Repo.insert!()

      assert {:ok, updated} = Settings.update_setting("test", "new")
      assert updated.value == "new"

      # Verify DB was updated
      assert Repo.get!(SiteSetting, setting.id).value == "new"
    end

    test "raises if setting not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Settings.update_setting("nonexistent", "value")
      end
    end

    test "updates caches after successful update" do
      %SiteSetting{name: "cached", value: "old"} |> Repo.insert!()

      # Populate cache
      assert Settings.get_setting("cached") == "old"
      assert [%{value: "old"}] = Settings.settings()

      # Update should refresh caches
      {:ok, _} = Settings.update_setting("cached", "new")

      assert Settings.get_setting("cached") == "new"
      assert [%{value: "new"}] = Settings.settings()
    end
  end

  describe "get_or_create_setting/3" do
    test "returns existing setting value" do
      %SiteSetting{name: "existing", value: "existing_value", group: "test"}
      |> Repo.insert!()

      value = Settings.get_or_create_setting("existing", "test", "default")
      assert value == "existing_value"
    end

    test "creates setting with default value if not exists" do
      value =
        Settings.get_or_create_setting("new_setting", "test", "default_value")

      assert value == "default_value"

      # Verify it was created in DB
      setting = Repo.get_by!(SiteSetting, name: "new_setting")
      assert setting.value == "default_value"
      assert setting.group == "test"
    end

    test "handles race condition when multiple processes create same setting" do
      # This test verifies the race condition handling in get_or_create_setting
      # by attempting to create the same setting multiple times
      value1 = Settings.get_or_create_setting("race_setting", "test", "default")
      value2 = Settings.get_or_create_setting("race_setting", "test", "default")

      assert value1 == "default"
      assert value2 == "default"

      # Should only have one setting in DB
      settings =
        Repo.all(from s in SiteSetting, where: s.name == "race_setting")

      assert length(settings) == 1
    end
  end

  describe "get_setting_safe/1" do
    test "returns setting value when exists" do
      %SiteSetting{name: "safe_setting", value: "safe_value"} |> Repo.insert!()
      assert Settings.get_setting_safe("safe_setting") == "safe_value"
    end

    test "returns nil when setting does not exist" do
      assert Settings.get_setting_safe("nonexistent") == nil
    end

    test "uses cache when available" do
      setting =
        %SiteSetting{name: "cached_safe", value: "cached"} |> Repo.insert!()

      # First call populates cache
      assert Settings.get_setting_safe("cached_safe") == "cached"

      # Update DB directly
      setting
      |> Ecto.Changeset.change(value: "updated")
      |> Repo.update!()

      # Should return cached value
      assert Settings.get_setting_safe("cached_safe") == "cached"
    end
  end

  describe "settings_grouped_by_scope/0" do
    test "groups settings by scope" do
      %SiteSetting{name: "setting1", value: "value1", group: "group1"}
      |> Repo.insert!()

      %SiteSetting{name: "setting2", value: "value2", group: "group1"}
      |> Repo.insert!()

      %SiteSetting{name: "setting3", value: "value3", group: "group2"}
      |> Repo.insert!()

      Settings.clear_cache()
      grouped = Settings.settings_grouped_by_scope()

      assert Map.has_key?(grouped, "group1")
      assert Map.has_key?(grouped, "group2")
      assert length(grouped["group1"]) == 2
      assert length(grouped["group2"]) == 1
    end
  end

  describe "setting_scopes/0" do
    test "returns unique list of scopes" do
      %SiteSetting{name: "s1", value: "v1", group: "scope1"} |> Repo.insert!()
      %SiteSetting{name: "s2", value: "v2", group: "scope1"} |> Repo.insert!()
      %SiteSetting{name: "s3", value: "v3", group: "scope2"} |> Repo.insert!()

      Settings.clear_cache()
      scopes = Settings.setting_scopes()

      assert length(scopes) == 2
      assert Enum.member?(scopes, "scope1")
      assert Enum.member?(scopes, "scope2")
    end
  end

  describe "clear_cache/0" do
    test "clears all settings caches" do
      %SiteSetting{name: "cache_test", value: "value"} |> Repo.insert!()

      # Populate cache
      _ = Settings.get_setting("cache_test")
      _ = Settings.settings()

      # Clear cache
      Settings.clear_cache()

      # Cache should be empty, so next call should hit DB
      # We can't directly verify cache is empty, but we can verify
      # that settings are still accessible (they'll be re-cached)
      assert Settings.get_setting("cache_test") == "value"
    end
  end

  describe "ensure_settings_exist/0" do
    test "creates default settings if they don't exist" do
      Settings.ensure_settings_exist()

      # Verify default settings were created
      assert Repo.get_by(SiteSetting, name: "site_name") != nil
      assert Repo.get_by(SiteSetting, name: "contact_email") != nil
      assert Repo.get_by(SiteSetting, name: "instagram") != nil
    end

    test "does not overwrite existing settings" do
      %SiteSetting{name: "site_name", value: "Custom Name", group: "general"}
      |> Repo.insert!()

      Settings.ensure_settings_exist()

      # Should not have changed
      setting = Repo.get_by!(SiteSetting, name: "site_name")
      assert setting.value == "Custom Name"
    end
  end
end
