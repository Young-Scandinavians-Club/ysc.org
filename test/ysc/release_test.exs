defmodule Ysc.ReleaseTest do
  use Ysc.DataCase, async: false

  alias Ysc.Release
  alias Ysc.Settings
  alias Ysc.SiteSettings.SiteSetting

  @moduletag skip_settings_setup: true

  setup do
    Repo.delete_all(SiteSetting)
    Settings.clear_cache()
    :ok
  end

  describe "wp_load/2" do
    test "returns error when export directory does not exist" do
      missing =
        Path.join(
          System.tmp_dir!(),
          "missing-wp-export-#{System.unique_integer()}"
        )

      assert {:error, message} = Release.wp_load(missing)
      assert message =~ "Export directory not found"
    end

    test "runs dry_run load for an empty export directory" do
      export_dir =
        System.tmp_dir!()
        |> Path.join("wp-export-#{System.unique_integer()}")
        |> tap(&File.mkdir_p!/1)

      on_exit(fn -> File.rm_rf!(export_dir) end)

      assert {:ok, result} = Release.wp_load(export_dir, dry_run: true)
      assert result == %{}
    end

    test "forwards only_emails to the load pipeline" do
      export_dir =
        System.tmp_dir!()
        |> Path.join("wp-export-#{System.unique_integer()}")
        |> tap(&File.mkdir_p!/1)

      users_json = Path.join(export_dir, "users.json")

      users_json
      |> File.write!(
        Jason.encode!([
          %{"wp_user_id" => "1", "email" => "keep@example.com"},
          %{"wp_user_id" => "2", "email" => "skip@example.com"}
        ])
      )

      on_exit(fn -> File.rm_rf!(export_dir) end)

      assert {:ok, _} =
               Release.wp_load(export_dir,
                 dry_run: true,
                 only_emails: ["keep@example.com"]
               )
    end
  end

  describe "wp_migration_unlock/0" do
    test "clears wp_migration_active when it is true" do
      %SiteSetting{
        name: "wp_migration_active",
        value: "true",
        group: "migration"
      }
      |> Repo.insert!()

      assert :ok = Release.wp_migration_unlock()
      assert Settings.get_setting_safe("wp_migration_active") == "false"
    end

    test "returns :ok without changing value when already false" do
      %SiteSetting{
        name: "wp_migration_active",
        value: "false",
        group: "migration"
      }
      |> Repo.insert!()

      assert :ok = Release.wp_migration_unlock()
      assert Settings.get_setting_safe("wp_migration_active") == "false"
    end

    test "returns :ok when wp_migration_active is unset" do
      assert :ok = Release.wp_migration_unlock()
      assert Settings.get_setting_safe("wp_migration_active") == nil
    end
  end
end
