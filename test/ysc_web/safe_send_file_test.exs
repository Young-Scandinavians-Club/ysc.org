defmodule YscWeb.SafeSendFileTest do
  use ExUnit.Case, async: true

  alias YscWeb.SafeSendFile

  import Plug.Conn
  import Plug.Test

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "safe-send-file-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "send_within/4 sends a file inside the root", %{root: root} do
    filename = "report.csv"
    File.write!(Path.join(root, filename), "a,b,c")

    conn =
      conn("/")
      |> put_resp_content_type("text/csv")

    assert {:ok, conn} = SafeSendFile.send_within(conn, 200, root, filename)
    assert conn.state == :file

    assert String.starts_with?(
             hd(get_resp_header(conn, "content-type")),
             "text/csv"
           )
  end

  test "send_within/4 rejects path traversal", %{root: root} do
    outside_dir = Path.dirname(root)

    outside =
      Path.join(
        outside_dir,
        "outside-#{System.unique_integer([:positive])}.txt"
      )

    File.write!(outside, "secret")
    on_exit(fn -> File.rm(outside) end)

    traversal = Path.relative_to(outside, root)
    conn = conn("/")

    assert :error = SafeSendFile.send_within(conn, 200, root, traversal)
  end

  test "send_within/4 rejects missing files", %{root: root} do
    conn = conn("/")

    assert :error = SafeSendFile.send_within(conn, 200, root, "missing.csv")
  end
end
