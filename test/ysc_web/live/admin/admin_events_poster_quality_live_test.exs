defmodule YscWeb.AdminEventsPosterQualityLiveTest do
  # Mutates the global :open_router app env and relies on shared Req.Test
  # stubs (the review runs in a task), so it must not run concurrently.
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.MerchFixtures, only: [image_fixture: 1]

  alias Ysc.OpenRouter.Mock

  @png File.read!(Path.expand("../../../support/fixtures/tiny.png", __DIR__))

  setup %{conn: conn} = context do
    Req.Test.set_req_test_from_context(context)

    prev_open_router = Application.get_env(:ysc, :open_router)
    prev_client = Application.get_env(:ysc, :open_router_client)

    # Start every test with the LLM review switched off; the "automated photo
    # check" describe turns it on.
    Application.put_env(:ysc, :open_router, api_key: nil)

    on_exit(fn ->
      restore(:open_router, prev_open_router)
      restore(:open_router_client, prev_client)
    end)

    admin = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  defp restore(key, nil), do: Application.delete_env(:ysc, key)
  defp restore(key, value), do: Application.put_env(:ysc, key, value)

  defp poster(width, height) do
    image_fixture(%{
      width: width,
      height: height,
      processing_state: :completed,
      optimized_image_path: "https://media.example.test/poster.png"
    })
  end

  defp edit_event(conn, admin, attrs \\ %{}) do
    event = event_fixture(Map.merge(%{organizer_id: admin.id}, attrs))
    {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")
    {event, view}
  end

  defp pick_cover(view, image) do
    send(view.pid, {YscWeb.MediaPickerComponent, :event_cover, image.id})
    render(view)
  end

  defp clear_cover(view) do
    send(view.pid, {YscWeb.MediaPickerComponent, :event_cover, :cleared})
    render(view)
  end

  describe "dimension warnings" do
    test "shows nothing when the cover is 16:9 and large enough", ctx do
      {_event, view} =
        edit_event(ctx.conn, ctx.admin, %{image_id: poster(1920, 1080).id})

      assert has_element?(view, "#event-cover-section")
      refute has_element?(view, "#cover-image-quality")
    end

    test "shows nothing when the event has no cover", ctx do
      {_event, view} = edit_event(ctx.conn, ctx.admin)

      refute has_element?(view, "#cover-image-quality")
    end

    test "warns about a cover that is not 16:9", ctx do
      {_event, view} =
        edit_event(ctx.conn, ctx.admin, %{image_id: poster(3000, 2000).id})

      assert has_element?(
               view,
               "#cover-image-quality-aspect_ratio",
               "3000×2000"
             )

      refute has_element?(view, "#cover-image-quality-low_resolution")
    end

    test "warns about a 16:9 cover that is too small", ctx do
      {_event, view} =
        edit_event(ctx.conn, ctx.admin, %{image_id: poster(1000, 562).id})

      assert has_element?(
               view,
               "#cover-image-quality-low_resolution",
               "1000×562"
             )

      refute has_element?(view, "#cover-image-quality-aspect_ratio")
    end

    test "shows both warnings for a small 4:3 cover", ctx do
      {_event, view} =
        edit_event(ctx.conn, ctx.admin, %{image_id: poster(800, 600).id})

      assert has_element?(view, "#cover-image-quality-aspect_ratio")
      assert has_element?(view, "#cover-image-quality-low_resolution")
    end

    test "says nothing about a cover whose size is unknown", ctx do
      unmeasured = image_fixture(%{width: nil, height: nil})

      {_event, view} =
        edit_event(ctx.conn, ctx.admin, %{image_id: unmeasured.id})

      refute has_element?(view, "#cover-image-quality")
    end

    test "re-checks when the cover is changed and when it is cleared", ctx do
      {event, view} = edit_event(ctx.conn, ctx.admin)

      pick_cover(view, poster(800, 600))
      assert has_element?(view, "#cover-image-quality-aspect_ratio")
      assert Ysc.Events.get_event!(event.id).image_id != nil

      pick_cover(view, poster(1920, 1080))
      refute has_element?(view, "#cover-image-quality")

      pick_cover(view, poster(800, 600))
      assert has_element?(view, "#cover-image-quality-aspect_ratio")

      clear_cover(view)
      refute has_element?(view, "#cover-image-quality")
    end
  end

  describe "cover changed by someone else" do
    defp broadcast_cover(view, event, image_id) do
      updated = %{Ysc.Events.get_event!(event.id) | image_id: image_id}

      send(
        view.pid,
        {Ysc.Events, %Ysc.MessagePassingEvents.EventUpdated{event: updated}}
      )

      render(view)
    end

    test "refreshes the warnings for the new cover", ctx do
      {event, view} =
        edit_event(ctx.conn, ctx.admin, %{image_id: poster(1920, 1080).id})

      refute has_element?(view, "#cover-image-quality")

      broadcast_cover(view, event, poster(800, 600).id)
      assert has_element?(view, "#cover-image-quality-aspect_ratio")

      broadcast_cover(view, event, poster(1920, 1080).id)
      refute has_element?(view, "#cover-image-quality")
    end
  end

  describe "automated photo check" do
    setup do
      Application.put_env(:ysc, :open_router,
        api_key: "test-key",
        vision_model: "test-vision-model"
      )

      Application.put_env(:ysc, :open_router_client, Mock)

      Req.Test.stub(Ysc.Media.PosterReview, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/png")
        |> Plug.Conn.send_resp(200, @png)
      end)

      :ok
    end

    test "flags a newly picked cover once the review finishes", ctx do
      {_event, view} = edit_event(ctx.conn, ctx.admin)

      pick_cover(view, poster(1920, 1080))
      render_async(view)

      assert has_element?(view, "#cover-image-quality-review")
      assert has_element?(view, "#cover-image-quality-review-embedded_text")
      refute has_element?(view, "#cover-image-quality-review-running")
    end

    test "does not review an existing cover just by opening the editor", ctx do
      {_event, view} =
        edit_event(ctx.conn, ctx.admin, %{image_id: poster(1920, 1080).id})

      render_async(view)

      refute has_element?(view, "#cover-image-quality-review")
      refute has_element?(view, "#cover-image-quality-review-running")
    end

    test "keeps the dimension warnings alongside the review", ctx do
      {_event, view} = edit_event(ctx.conn, ctx.admin)

      pick_cover(view, poster(800, 600))
      render_async(view)

      assert has_element?(view, "#cover-image-quality-aspect_ratio")
      assert has_element?(view, "#cover-image-quality-review-embedded_text")
    end

    test "the admin can dismiss the review and keep the photo", ctx do
      {event, view} = edit_event(ctx.conn, ctx.admin)
      image = poster(1920, 1080)

      pick_cover(view, image)
      render_async(view)

      view |> element("#cover-image-quality-review-dismiss") |> render_click()

      refute has_element?(view, "#cover-image-quality-review")
      assert Ysc.Events.get_event!(event.id).image_id == image.id
    end

    test "an echo of our own save does not cancel the running review", ctx do
      {event, view} = edit_event(ctx.conn, ctx.admin)
      image = poster(1920, 1080)

      pick_cover(view, image)
      broadcast_cover(view, event, image.id)
      render_async(view)

      assert has_element?(view, "#cover-image-quality-review-embedded_text")
    end

    test "drops the review when the cover is cleared", ctx do
      {_event, view} = edit_event(ctx.conn, ctx.admin)

      pick_cover(view, poster(1920, 1080))
      render_async(view)
      assert has_element?(view, "#cover-image-quality-review")

      clear_cover(view)

      refute has_element?(view, "#cover-image-quality")
    end

    test "is skipped entirely when OpenRouter is not configured", ctx do
      Application.put_env(:ysc, :open_router, api_key: nil)
      {_event, view} = edit_event(ctx.conn, ctx.admin)

      pick_cover(view, poster(1920, 1080))
      render_async(view)

      refute has_element?(view, "#cover-image-quality")
    end

    test "shows no review when the image cannot be downloaded", ctx do
      Req.Test.stub(Ysc.Media.PosterReview, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      {_event, view} = edit_event(ctx.conn, ctx.admin)

      pick_cover(view, poster(1920, 1080))
      render_async(view)

      refute has_element?(view, "#cover-image-quality")
    end
  end
end
