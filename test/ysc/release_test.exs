defmodule Ysc.ReleaseTest do
  use Ysc.DataCase, async: false

  alias Ysc.Settings
  alias Ysc.SiteSettings.SiteSetting

  @moduletag skip_settings_setup: true

  setup do
    Repo.delete_all(SiteSetting)
    Settings.clear_cache()
    :ok
  end
end
