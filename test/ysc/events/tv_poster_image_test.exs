defmodule Ysc.Events.TvPosterImageTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.TvPosterImage

  describe "normalize_format/1" do
    test "defaults invalid formats to png" do
      assert TvPosterImage.normalize_format(nil) == "png"
      assert TvPosterImage.normalize_format("jpg") == "jpeg"
      assert TvPosterImage.normalize_format(" WEBP ") == "webp"
      assert TvPosterImage.normalize_format("gif") == "png"
    end
  end

  describe "mime_type/1" do
    test "returns content types for supported formats" do
      assert TvPosterImage.mime_type("png") == "image/png"
      assert TvPosterImage.mime_type("jpeg") == "image/jpeg"
      assert TvPosterImage.mime_type("webp") == "image/webp"
    end
  end

  describe "build_html/1 and capture/2" do
    test "renders capture document with event details" do
      event = event_fixture(%{title: "Poster Night"})
      event = Events.get_event_for_tv_poster(event.id)

      html =
        TvPosterImage.build_html(%{
          event: event,
          event_url: "https://ysc.org/events/#{event.id}",
          sold_out: false,
          selling_fast: true
        })

      assert html =~ "Poster Night"
      assert html =~ "event-tv-poster"
    end

    test "capture returns stub image bytes in test" do
      event = event_fixture() |> then(&Events.get_event_for_tv_poster(&1.id))

      assert {:ok, binary} =
               TvPosterImage.capture(%{
                 event: event,
                 event_url: "https://ysc.org/events/#{event.id}"
               })

      assert binary |> binary_part(0, 4) == <<137, 80, 78, 71>>
    end

    test "capture respects format option" do
      event = event_fixture() |> then(&Events.get_event_for_tv_poster(&1.id))

      assert {:ok, _binary} =
               TvPosterImage.capture(
                 %{
                   event: event,
                   event_url: "https://ysc.org/events/#{event.id}"
                 },
                 format: "jpeg"
               )
    end
  end
end
