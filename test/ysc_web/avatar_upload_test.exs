defmodule YscWeb.AvatarUploadTest do
  use ExUnit.Case, async: true

  alias YscWeb.AvatarUpload

  describe "upload outcome helpers" do
    test "upload_succeeded?/1" do
      assert AvatarUpload.upload_succeeded?([{:ok, %{id: "1"}}])
      refute AvatarUpload.upload_succeeded?([{:error, :boom}])
      refute AvatarUpload.upload_succeeded?([])
    end

    test "upload_failed?/1" do
      assert AvatarUpload.upload_failed?([{:error, :boom}])
      refute AvatarUpload.upload_failed?([{:ok, %{id: "1"}}])
      refute AvatarUpload.upload_failed?([])
    end
  end
end
