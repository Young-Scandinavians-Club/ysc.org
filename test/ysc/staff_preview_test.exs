defmodule Ysc.StaffPreviewTest do
  use Ysc.DataCase, async: true

  alias Ysc.StaffPreview

  import Ysc.AccountsFixtures

  describe "staff_content_preview?/1" do
    test "returns true for admin and volunteer users" do
      assert StaffPreview.staff_content_preview?(user_fixture(%{role: :admin}))

      assert StaffPreview.staff_content_preview?(
               user_fixture(%{role: :volunteer})
             )
    end

    test "returns false for members and nil" do
      refute StaffPreview.staff_content_preview?(user_fixture(%{role: :member}))
      refute StaffPreview.staff_content_preview?(nil)
    end
  end
end
