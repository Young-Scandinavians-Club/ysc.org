defmodule YscWeb.EventTvPosterControllerTest do
  use YscWeb.ConnCase

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  describe "GET /admin/events/:id/tv-poster" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{title: "Tahoe Cabin Social"})
      %{conn: log_in_user(conn, admin), event: event}
    end

    test "renders the TV poster preview for admins", %{conn: conn, event: event} do
      conn = get(conn, ~p"/admin/events/#{event.id}/tv-poster")

      html = html_response(conn, 200)
      assert html =~ "event-tv-poster"
      assert html =~ "event-tv-poster-qr"
      assert html =~ "Scan for details"
      assert html =~ "<svg"
      assert html =~ "Tahoe Cabin Social"
      assert html =~ "TV poster preview"
      assert html =~ "View as PNG image"
      assert html =~ "/tv-poster/image"
    end

    test "returns 404 when the event does not exist", %{conn: conn} do
      missing_id = Ecto.ULID.generate()

      conn = get(conn, ~p"/admin/events/#{missing_id}/tv-poster")
      assert html_response(conn, 404)
    end

    test "renders PNG image at /tv-poster/image", %{conn: conn, event: event} do
      conn = get(conn, ~p"/admin/events/#{event.id}/tv-poster/image")

      assert response(conn, 200)

      assert get_resp_header(conn, "content-type") == [
               "image/png; charset=utf-8"
             ]

      assert conn.resp_body |> binary_part(0, 4) == <<137, 80, 78, 71>>
    end

    test "supports format=webp query param", %{conn: conn, event: event} do
      conn =
        get(conn, ~p"/admin/events/#{event.id}/tv-poster/image?format=webp")

      assert response(conn, 200)

      assert get_resp_header(conn, "content-type") == [
               "image/webp; charset=utf-8"
             ]
    end

    test "supports format=jpeg query param", %{conn: conn, event: event} do
      conn =
        get(conn, ~p"/admin/events/#{event.id}/tv-poster/image?format=jpeg")

      assert response(conn, 200)

      assert get_resp_header(conn, "content-type") == [
               "image/jpeg; charset=utf-8"
             ]
    end

    test "returns 503 when image capture fails", %{conn: conn, event: event} do
      previous_module = Application.get_env(:ysc, :tv_poster_image_module)

      on_exit(fn ->
        Application.put_env(:ysc, :tv_poster_image_module, previous_module)
      end)

      Application.put_env(
        :ysc,
        :tv_poster_image_module,
        Ysc.Events.TvPosterImage.ErrorStub
      )

      conn = get(conn, ~p"/admin/events/#{event.id}/tv-poster/image")

      assert response(conn, 503)
      assert conn.resp_body =~ "Could not generate poster image"
    end

    test "redirects unauthenticated users", %{event: event} do
      conn =
        build_conn()
        |> get(~p"/admin/events/#{event.id}/tv-poster")

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
