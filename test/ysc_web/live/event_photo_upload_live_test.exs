defmodule YscWeb.EventPhotoUploadLiveTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.EventPhotos
  alias Ysc.Events.Ticket
  alias Ysc.Repo

  setup %{conn: conn} do
    prev = Application.get_env(:ysc, :google_photos, [])

    Application.put_env(
      :ysc,
      :google_photos,
      Keyword.put(prev, :dev_stub, true)
    )

    on_exit(fn -> Application.put_env(:ysc, :google_photos, prev) end)

    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id, state: :published})
    {:ok, collection} = EventPhotos.ensure_collection_for_event(event)
    buyer = user_fixture()

    tier = ticket_tier_fixture(%{event_id: event.id, type: :paid})

    %Ticket{
      id: Ecto.ULID.generate(),
      event_id: event.id,
      user_id: buyer.id,
      ticket_tier_id: tier.id,
      status: :confirmed,
      expires_at:
        DateTime.add(DateTime.utc_now(), 1, :day) |> DateTime.truncate(:second)
    }
    |> Repo.insert!()

    conn =
      log_in_user(conn, buyer)

    %{
      conn: conn,
      event: event,
      collection: collection,
      buyer: buyer,
      upload_path: ~p"/events/photos/#{collection.upload_token}"
    }
  end

  test "renders upload page for authorized attendee", %{
    conn: conn,
    upload_path: path
  } do
    {:ok, view, html} = live(conn, path)

    assert html =~ "Share your photos"
    assert html =~ "videos"
    assert html =~ "up to 30 files per batch"
    assert has_element?(view, "#event-photo-upload-form")
    assert has_element?(view, "#photo-drop-zone")
  end

  test "redirects unauthorized users", %{collection: collection} do
    other = user_fixture()
    conn = build_conn() |> log_in_user(other)

    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/events/photos/#{collection.upload_token}")
  end

  test "invalid token redirects home", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/events/photos/#{Ecto.UUID.generate()}")
  end

  test "shows friendly message for unexpected upload validation errors" do
    message =
      YscWeb.UploadErrors.error_to_string(
        {:writer_failure, :timeout},
        :event_photo
      )

    assert message =~ "Something went wrong uploading that file"
    assert message =~ "Please try again"
  end
end
