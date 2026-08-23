defmodule YscWeb.EventPhotoUploadLiveTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.EventPhotos
  alias Ysc.Events.Ticket
  alias Ysc.Repo

  @tiny_png Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            )

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

  test "flags an unsupported file extension immediately and blocks submit", %{
    conn: conn,
    upload_path: path
  } do
    {:ok, view, _html} = live(conn, path)

    upload =
      file_input(view, "#event-photo-upload-form", :photos, [
        %{
          last_modified: System.system_time(:millisecond),
          name: "flags.avif",
          content: @tiny_png,
          type: "image/avif"
        }
      ])

    render_upload(upload, "flags.avif")
    render_change(view, "validate", %{})

    assert has_element?(
             view,
             "div[data-filename='flags.avif'].border-red-400",
             "File type is not supported."
           )

    assert has_element?(view, "#submit-photos-btn[disabled]")
  end

  test "shows a prominent banner if an unsupported file somehow reaches submit",
       %{conn: conn, upload_path: path} do
    {:ok, view, _html} = live(conn, path)

    upload =
      file_input(view, "#event-photo-upload-form", :photos, [
        %{
          last_modified: System.system_time(:millisecond),
          name: "flags.avif",
          content: @tiny_png,
          type: "image/avif"
        }
      ])

    render_upload(upload, "flags.avif")

    # The submit button is disabled client-side once a file is flagged, but
    # the "upload" handler is still the last line of defense — simulate a
    # bypassed disabled attribute by submitting the form event directly,
    # without ever firing "validate".
    html = render_submit(view, "upload")

    assert html =~ "We couldn&#39;t upload everything"

    assert has_element?(
             view,
             "div[data-filename='flags.avif'].border-red-400",
             "File type is not supported."
           )

    assert has_element?(view, "#submit-photos-btn[disabled]")
  end

  test "shows a too-many-files banner when the batch exceeds the max entry count",
       %{conn: conn, upload_path: path} do
    {:ok, view, _html} = live(conn, path)

    entries =
      for i <- 1..31 do
        %{
          last_modified: System.system_time(:millisecond),
          name: "photo#{i}.png",
          content: @tiny_png,
          type: "image/png"
        }
      end

    upload = file_input(view, "#event-photo-upload-form", :photos, entries)
    html = render_upload(upload, "photo1.png")

    assert html =~ "You can upload up to 30 files per batch"
  end

  test "removing a flagged file clears its error and unblocks submit of the rest",
       %{conn: conn, upload_path: path} do
    {:ok, view, _html} = live(conn, path)

    good =
      file_input(view, "#event-photo-upload-form", :photos, [
        %{
          last_modified: System.system_time(:millisecond),
          name: "good.png",
          content: @tiny_png,
          type: "image/png"
        }
      ])

    assert render_upload(good, "good.png") =~ "Ready"

    bad =
      file_input(view, "#event-photo-upload-form", :photos, [
        %{
          last_modified: System.system_time(:millisecond),
          name: "bad.avif",
          content: @tiny_png,
          type: "image/avif"
        }
      ])

    render_upload(bad, "bad.avif")
    render_change(view, "validate", %{})

    assert has_element?(
             view,
             "div[data-filename='bad.avif'].border-red-400",
             "File type is not supported."
           )

    assert has_element?(view, "#submit-photos-btn[disabled]")

    html =
      view
      |> element("div[data-filename='bad.avif'] button[aria-label='Remove']")
      |> render_click()

    refute html =~ "File type is not supported."
    assert has_element?(view, "div[data-filename='good.png']")
    refute has_element?(view, "div[data-filename='bad.avif']")
    refute has_element?(view, "#submit-photos-btn[disabled]")
  end

  test "uploads multiple photos from a single file_input (LiveView 1.2.10)",
       %{conn: conn, upload_path: path} do
    {:ok, view, _html} = live(conn, path)

    upload =
      file_input(view, "#event-photo-upload-form", :photos, [
        %{
          last_modified: System.system_time(:millisecond),
          name: "one.png",
          content: @tiny_png,
          type: "image/png"
        },
        %{
          last_modified: System.system_time(:millisecond),
          name: "two.png",
          content: @tiny_png,
          type: "image/png"
        }
      ])

    assert render_upload(upload, "one.png") =~ "Ready"
    assert render_upload(upload, "two.png") =~ "Ready"

    assert has_element?(view, "div[data-filename='one.png']")
    assert has_element?(view, "div[data-filename='two.png']")
    assert has_element?(view, "#submit-photos-btn")
    refute has_element?(view, "#submit-photos-btn[disabled]")
  end

  test "cancelling a ready upload removes it from the queue",
       %{conn: conn, upload_path: path} do
    {:ok, view, _html} = live(conn, path)

    upload =
      file_input(view, "#event-photo-upload-form", :photos, [
        %{
          last_modified: System.system_time(:millisecond),
          name: "drop-me.png",
          content: @tiny_png,
          type: "image/png"
        }
      ])

    assert render_upload(upload, "drop-me.png") =~ "Ready"
    assert has_element?(view, "div[data-filename='drop-me.png']")

    view
    |> element("div[data-filename='drop-me.png'] button[aria-label='Remove']")
    |> render_click()

    refute has_element?(view, "div[data-filename='drop-me.png']")
  end

  test "submits queued files once uploads finish and shows the thank-you state",
       %{conn: conn, upload_path: path} do
    {:ok, view, _html} = live(conn, path)

    upload =
      file_input(view, "#event-photo-upload-form", :photos, [
        %{
          last_modified: System.system_time(:millisecond),
          name: "party.png",
          content: @tiny_png,
          type: "image/png"
        }
      ])

    assert render_upload(upload, "party.png") =~ "Ready"

    html = render_submit(view, "upload")

    assert html =~ "Tusen tack"
  end
end
