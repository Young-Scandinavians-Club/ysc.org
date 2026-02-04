defmodule YscWeb.UploadComponentTest do
  use Ysc.DataCase, async: true
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias YscWeb.UploadComponent

  defp new_socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  describe "mount/1" do
    test "initializes socket with upload configuration" do
      socket = new_socket()
      {:ok, socket} = UploadComponent.mount(socket)

      assert socket.assigns.uploads != nil
      upload_config = socket.assigns.uploads.upload_component_file
      assert upload_config != nil
      # Accept is stored as a string or list
      accept = upload_config.accept
      assert accept != nil
      # Verify it contains the expected extensions
      accept_str =
        if is_list(accept), do: Enum.join(accept, ","), else: to_string(accept)

      assert String.contains?(accept_str, "jpg")
      assert String.contains?(accept_str, "png")
      assert upload_config.max_entries == 1
      # Verify upload configuration is properly set up
      assert Map.has_key?(upload_config, :ref)
    end
  end

  describe "update/2" do
    test "assigns provided assigns to socket" do
      socket = new_socket()
      assigns = %{id: "test-id", user_id: "user-123"}

      {:ok, updated_socket} = UploadComponent.update(assigns, socket)

      assert updated_socket.assigns.id == "test-id"
      assert updated_socket.assigns.user_id == "user-123"
    end

    test "preserves existing assigns" do
      socket = new_socket(%{existing_assign: "value"})
      assigns = %{id: "test-id"}

      {:ok, updated_socket} = UploadComponent.update(assigns, socket)

      assert updated_socket.assigns.existing_assign == "value"
      assert updated_socket.assigns.id == "test-id"
    end
  end

  describe "handle_event/3" do
    test "validate event returns socket unchanged" do
      socket = new_socket(%{id: "test-id"})

      {:noreply, updated_socket} =
        UploadComponent.handle_event("validate", %{}, socket)

      assert updated_socket == socket
    end

    @tag :skip
    test "cancel event cancels upload" do
      # Note: This test requires actual upload entries which are difficult
      # to set up in unit tests. Test this through integration tests instead.
      socket = new_socket(%{id: "test-id"})
      {:ok, socket} = UploadComponent.mount(socket)

      ref = "entry-ref-123"

      # cancel_upload requires actual upload entries
      {:noreply, updated_socket} =
        UploadComponent.handle_event("cancel", %{"ref" => ref}, socket)

      assert %Phoenix.LiveView.Socket{} = updated_socket
    end

    test "save event structure", %{} do
      user = user_fixture()
      socket = new_socket(%{id: "test-id", user_id: user.id})
      {:ok, socket} = UploadComponent.mount(socket)

      # Test that save event can be called
      # Note: This will call YscWeb.Uploads.consume_entries which requires
      # actual upload entries. For full testing, use integration tests.
      {:noreply, updated_socket} =
        UploadComponent.handle_event("save", %{}, socket)

      # Verify socket structure is maintained
      assert %Phoenix.LiveView.Socket{} = updated_socket
    end
  end

  # Note: error_to_string/1 is private, tested indirectly through render

  describe "render/1" do
    test "renders upload form with correct structure", %{} do
      user = user_fixture()
      html = render_component(UploadComponent, id: "test-id", user_id: user.id)

      assert html =~ "upload-component"
      assert html =~ "test-id-upload-form"
      assert html =~ "phx-change=\"validate\""
      assert html =~ "phx-submit=\"save\""
      assert html =~ "data-user_id"
    end

    test "renders upload area when no entries", %{} do
      user = user_fixture()
      html = render_component(UploadComponent, id: "test-id", user_id: user.id)

      assert html =~ "Click to upload"
      assert html =~ "drag and drop"
      assert html =~ "SVG, PNG, JPG, JPEG or GIF"
    end

    test "renders file input", %{} do
      user = user_fixture()
      html = render_component(UploadComponent, id: "test-id", user_id: user.id)

      # The component renders an input with the upload name
      assert html =~ "upload_component_file"
      assert html =~ "type=\"file\""
    end
  end
end
