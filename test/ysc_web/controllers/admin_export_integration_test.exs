defmodule YscWeb.AdminExportIntegrationTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias YscWeb.Workers.UserExporter

  test "admin can download CSV after UserExporter completes", %{conn: conn} do
    admin = user_fixture(%{state: :active, role: :admin})
    channel = "exporter:#{admin.id}"
    :ok = YscWeb.Endpoint.subscribe(channel)

    job = %Oban.Job{
      args: %{
        "channel" => channel,
        "fields" => ["id", "email"],
        "only_subscribed" => false,
        "created_by_user_id" => admin.id
      },
      worker: "YscWeb.Workers.UserExporter",
      queue: "exports"
    }

    assert :ok = UserExporter.perform(job)

    path =
      receive do
        %Phoenix.Socket.Broadcast{event: "user_export:complete", payload: p} ->
          p
      after
        15_000 -> flunk("no user_export:complete broadcast")
      end

    filename = path |> String.replace_prefix("/admin/exports/", "")
    exports_root = Path.join([:code.priv_dir(:ysc), "static", "exports"])
    on_exit(fn -> File.rm(Path.join(exports_root, filename)) end)

    conn = conn |> log_in_user(admin) |> get(path)

    assert conn.status == 200

    assert String.starts_with?(
             hd(get_resp_header(conn, "content-type")),
             "text/csv"
           )
  end

  test "LiveView download-export reads CSV from disk after export completes", %{
    conn: conn
  } do
    admin = user_fixture(%{state: :active, role: :admin})
    conn = log_in_user(conn, admin)
    _user = user_fixture(%{first_name: "Export", last_name: "Row"})

    {:ok, view, _html} = live(conn, ~p"/admin/users")

    view
    |> form("form[phx-submit=export-csv]", %{
      "csv_export" => %{
        "id" => "true",
        "email" => "true",
        "first_name" => "false",
        "last_name" => "false",
        "phone_number" => "false",
        "state" => "false",
        "address" => "false",
        "only_subscribers" => "false"
      }
    })
    |> render_submit()

    assert has_element?(view, "#download-user-export-button")
    assert render_click(view, "download-export") =~ "Download file"
  end

  test "missing export file returns 404 not 406", %{conn: conn} do
    admin = user_fixture(%{state: :active, role: :admin})

    filename =
      "ysc-user-export-2026-05-31-#{admin.id}-#{Ecto.ULID.generate()}.csv"

    conn = conn |> log_in_user(admin) |> get("/admin/exports/#{filename}")

    assert conn.status == 404
  end
end
