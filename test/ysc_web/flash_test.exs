defmodule YscWeb.FlashTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.ConnTest

  alias YscWeb.Flash

  defp conn_with_flash(conn) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> fetch_flash()
  end

  describe "put_toast/4 for Plug.Conn" do
    test "stores info flash and optional title flash", %{conn: conn} do
      conn =
        conn
        |> conn_with_flash()
        |> Flash.put_toast(:info, "Saved.", title: "Done")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Saved."
      assert Phoenix.Flash.get(conn.assigns.flash, "info_toast_title") == "Done"
    end

    test "success/3 and error/3 delegate to put_toast", %{conn: conn} do
      conn =
        conn
        |> conn_with_flash()
        |> Flash.success("OK")
        |> Flash.error("Bad")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "OK"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Bad"
    end

    test "success_with_title and error_with_title set title flashes", %{
      conn: conn
    } do
      conn =
        conn
        |> conn_with_flash()
        |> Flash.success_with_title("Payment", "Confirmed.")
        |> Flash.error_with_title("Form", "Invalid.")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Confirmed."

      assert Phoenix.Flash.get(conn.assigns.flash, "info_toast_title") ==
               "Payment"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid."

      assert Phoenix.Flash.get(conn.assigns.flash, "error_toast_title") ==
               "Form"
    end
  end

  describe "send_toast/3" do
    test "returns a toast id from LiveToast" do
      assert is_binary(Flash.send_toast(:info, "Hello"))
    end
  end
end
