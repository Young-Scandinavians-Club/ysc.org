defmodule YscWeb.UploadErrorsTest do
  use ExUnit.Case, async: true

  alias YscWeb.UploadErrors

  describe "error_to_string/1 default variant" do
    test "formats standard upload validation errors" do
      assert UploadErrors.error_to_string(:too_large) == "Too large"

      assert UploadErrors.error_to_string(:not_accepted) ==
               "You have selected an unacceptable file type"

      assert UploadErrors.error_to_string(:too_many_files) ==
               "You have selected too many files"

      assert UploadErrors.error_to_string(:unknown) == "An error occurred"
    end
  end

  describe "error_to_string/2 :admin variant" do
    test "includes external client failure copy" do
      message = UploadErrors.error_to_string(:external_client_failure, :admin)

      assert message =~ "Upload failed"
      assert message =~ "browser console"
    end

    test "falls back to generic admin message" do
      assert UploadErrors.error_to_string(:unknown, :admin) ==
               "An error occurred"
    end
  end

  describe "error_to_string/2 :avatar variant" do
    test "uses profile photo copy" do
      assert UploadErrors.error_to_string(:too_large, :avatar) ==
               "Image must be under 10 MB"

      assert UploadErrors.error_to_string(:not_accepted, :avatar) =~ "JPG"

      assert UploadErrors.error_to_string(:too_many_files, :avatar) =~
               "one photo"

      assert UploadErrors.error_to_string(:unknown, :avatar) == "Upload failed"
    end
  end

  describe "error_to_string/2 :expense variant" do
    test "uses reimbursement upload copy" do
      assert UploadErrors.error_to_string(:too_large, :expense) =~ "10MB"
      assert UploadErrors.error_to_string(:not_accepted, :expense) =~ "PDF"

      assert UploadErrors.error_to_string(:too_many_files, :expense) =~
               "Too many files"

      assert UploadErrors.error_to_string({:writer_failure, :timeout}, :expense) =~
               "Something went wrong uploading that file"
    end
  end

  describe "error_to_string/2 :event_photo variant" do
    test "uses event photo batch copy" do
      assert UploadErrors.error_to_string(:too_large, :event_photo) =~ "200 MB"

      assert UploadErrors.error_to_string(:too_many_files, :event_photo) =~
               "30 files"

      assert UploadErrors.error_to_string(:not_accepted, :event_photo) =~
               "photo or video"

      assert UploadErrors.error_to_string(
               {:writer_failure, :timeout},
               :event_photo
             ) =~
               "Something went wrong uploading that file"
    end
  end
end
