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

  describe "hash_assigns/1 and hash_event/1" do
    test "is stable for the same visible poster values" do
      assigns = poster_assigns()

      hash = TvPosterImage.hash_assigns(assigns)

      assert hash == TvPosterImage.hash_assigns(assigns)
      assert hash =~ ~r/^[0-9a-f]{64}$/
    end

    test "changes when title, date, price, cover, or badges change" do
      assigns = poster_assigns()
      original = TvPosterImage.hash_assigns(assigns)

      refute original ==
               hash_with(assigns, fn event ->
                 Map.put(event, :title, "New Title")
               end)

      refute original ==
               hash_with(assigns, fn event ->
                 Map.put(event, :start_date, ~D[2027-01-15])
               end)

      refute original ==
               hash_with(assigns, fn event ->
                 Map.put(event, :pricing_info, %{display_text: "From $10.00"})
               end)

      refute original ==
               hash_with(assigns, fn event ->
                 Map.put(event, :image, %{
                   raw_image_path: "/images/other.jpg",
                   optimized_image_path: nil
                 })
               end)

      refute original ==
               hash_with(assigns, fn event ->
                 Map.put(event, :tickets_tbd, true)
               end)

      refute original ==
               TvPosterImage.hash_assigns(Map.put(assigns, :sold_out, true))

      refute original ==
               TvPosterImage.hash_assigns(Map.put(assigns, :selling_fast, true))
    end

    test "hash_event/1 matches hash_assigns/1 of assigns_for_event/1" do
      event =
        event_fixture(%{title: "Hash Night"})
        |> then(&Events.get_event_for_tv_poster(&1.id))

      assert TvPosterImage.hash_event(event) ==
               event
               |> TvPosterImage.assigns_for_event()
               |> TvPosterImage.hash_assigns()
    end

    test "does not HEEx-render the capture document" do
      html = TvPosterImage.build_html(poster_assigns())
      hash = TvPosterImage.hash_assigns(poster_assigns())

      assert html =~ "event-tv-poster"
      refute hash == :crypto.hash(:sha256, html) |> Base.encode16(case: :lower)
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

  defp poster_assigns(overrides \\ %{}) do
    event =
      Map.merge(
        %{
          id: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
          title: "Poster Night",
          description: "A night at the hall",
          location_name: "The Hall",
          start_date: ~D[2026-12-01],
          start_time: ~T[19:00:00],
          end_date: ~D[2026-12-01],
          end_time: ~T[22:00:00],
          state: :published,
          tickets_tbd: false,
          ticket_tiers: [],
          image: nil,
          pricing_info: %{display_text: "$25.00"}
        },
        Map.get(overrides, :event, %{})
      )

    %{
      event: event,
      event_url: "https://ysc.org/events/#{event.id}",
      asset_base_url: "https://ysc.org/",
      sold_out: false,
      selling_fast: false
    }
    |> Map.merge(Map.delete(overrides, :event))
  end

  defp hash_with(assigns, fun) do
    event = fun.(assigns.event)
    TvPosterImage.hash_assigns(%{assigns | event: event})
  end
end
