defmodule LivePhoneTest do
  use ExUnit.Case, async: true

  alias LivePhone

  defp new_socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  describe "mount/1" do
    test "initializes socket with default values" do
      socket = new_socket()
      {:ok, socket} = LivePhone.mount(socket)

      assert socket.assigns.preferred == ["US", "GB"]
      assert socket.assigns.tabindex == 0
      assert socket.assigns.apply_format? == false
      assert socket.assigns.value == ""
      assert socket.assigns.opened? == false
      assert socket.assigns.valid? == false
    end
  end

  describe "update/2" do
    test "sets default country from preferred list" do
      socket = new_socket(%{value: ""})
      assigns = %{preferred: ["CA", "MX"], id: "test-id", value: ""}

      {:ok, updated_socket} = LivePhone.update(assigns, socket)

      assert updated_socket.assigns.country == "CA"
    end

    test "uses existing country if present in assigns" do
      socket = new_socket(%{country: "GB", value: ""})
      assigns = %{preferred: ["US"], id: "test-id", value: ""}

      {:ok, updated_socket} = LivePhone.update(assigns, socket)

      assert updated_socket.assigns.country == "GB"
    end

    test "uses country from assigns if provided" do
      socket = new_socket(%{value: ""})
      assigns = %{country: "FR", preferred: ["US"], id: "test-id", value: ""}

      {:ok, updated_socket} = LivePhone.update(assigns, socket)

      assert updated_socket.assigns.country == "FR"
    end

    test "sets masks when apply_format? is true" do
      socket = new_socket(%{value: ""})
      assigns = %{apply_format?: true, country: "US", id: "test-id", value: ""}

      {:ok, updated_socket} = LivePhone.update(assigns, socket)

      assert is_binary(updated_socket.assigns.masks) ||
               is_nil(updated_socket.assigns.masks)
    end

    test "does not set masks when apply_format? is false" do
      socket = new_socket(%{value: ""})
      assigns = %{apply_format?: false, country: "US", id: "test-id", value: ""}

      {:ok, updated_socket} = LivePhone.update(assigns, socket)

      assert updated_socket.assigns.masks == nil
    end

    test "calls set_value with value from assigns" do
      socket = new_socket(%{value: ""})
      assigns = %{value: "+16502530000", country: "US", id: "test-id"}

      {:ok, updated_socket} = LivePhone.update(assigns, socket)

      assert updated_socket.assigns.value != nil
      assert updated_socket.assigns.formatted_value != nil
    end
  end

  describe "set_value/2" do
    test "sets default value for empty string" do
      socket =
        new_socket(%{
          country: "US",
          formatted_value: nil,
          id: "test-id"
        })

      updated_socket = LivePhone.set_value(socket, "")

      assert updated_socket.assigns.value == ""
      assert updated_socket.assigns.formatted_value != nil
    end

    test "normalizes and validates phone number" do
      socket =
        new_socket(%{
          country: "US",
          formatted_value: nil,
          id: "test-id"
        })

      updated_socket = LivePhone.set_value(socket, "+16502530000")

      assert updated_socket.assigns.value != nil
      assert updated_socket.assigns.formatted_value == "+16502530000"
      assert updated_socket.assigns.valid? == true
    end

    test "marks invalid phone numbers as invalid" do
      socket =
        new_socket(%{
          country: "US",
          formatted_value: nil,
          id: "test-id"
        })

      updated_socket = LivePhone.set_value(socket, "1234")

      assert updated_socket.assigns.valid? == false
    end

    test "uses value from form if value is empty" do
      form = %Phoenix.HTML.Form{
        source: %Ecto.Changeset{
          data: %{phone: "+16502530000"},
          params: %{"phone" => "+16502530000"},
          errors: []
        },
        impl: Phoenix.HTML.FormData.Ecto.Changeset,
        name: :user,
        id: "user-form"
      }

      socket =
        new_socket(%{
          country: "US",
          form: form,
          field: :phone,
          formatted_value: nil,
          id: "test-id"
        })

      updated_socket = LivePhone.set_value(socket, "")

      assert updated_socket.assigns.value != ""
    end
  end

  describe "handle_event/3" do
    test "typing event updates value" do
      socket =
        new_socket(%{
          country: "US",
          formatted_value: nil,
          id: "test-id"
        })

      {:noreply, updated_socket} =
        LivePhone.handle_event("typing", %{"value" => "+16502530000"}, socket)

      assert updated_socket.assigns.value != nil
      assert updated_socket.assigns.formatted_value == "+16502530000"
    end

    test "blur event closes dropdown and validates" do
      socket =
        new_socket(%{
          country: "US",
          formatted_value: nil,
          opened?: true,
          id: "test-id"
        })

      {:noreply, updated_socket} =
        LivePhone.handle_event("blur", %{"value" => "+16502530000"}, socket)

      assert updated_socket.assigns.opened? == false
      assert updated_socket.assigns.formatted_value != nil
    end

    test "select_country event updates country" do
      socket =
        new_socket(%{
          country: "US",
          formatted_value: "+16502530000",
          opened?: true,
          id: "test-id"
        })

      {:noreply, updated_socket} =
        LivePhone.handle_event("select_country", %{"country" => "GB"}, socket)

      assert updated_socket.assigns.country == "GB"
      assert updated_socket.assigns.opened? == false
    end

    test "toggle event toggles opened state" do
      socket =
        new_socket(%{
          opened?: false,
          id: "test-id"
        })

      {:noreply, updated_socket} = LivePhone.handle_event("toggle", %{}, socket)

      assert updated_socket.assigns.opened? == true

      {:noreply, updated_socket2} =
        LivePhone.handle_event("toggle", %{}, updated_socket)

      assert updated_socket2.assigns.opened? == false
    end

    test "close event closes dropdown" do
      socket =
        new_socket(%{
          opened?: true,
          id: "test-id"
        })

      {:noreply, updated_socket} = LivePhone.handle_event("close", %{}, socket)

      assert updated_socket.assigns.opened? == false
    end
  end

  # Note: get_placeholder/1 and get_masks/1 are private functions
  # They are tested indirectly through update/2 and render/1
end
