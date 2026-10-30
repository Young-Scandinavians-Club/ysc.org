defmodule Ysc.Events.TvPosterImageTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.TvPosterImage
  alias Ysc.Media.Image

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

    test "changes when the alt text of an Image struct changes" do
      assigns = poster_assigns()

      with_image = fn image_attrs ->
        hash_with(assigns, fn event ->
          Map.put(
            event,
            :image,
            struct!(
              Image,
              Map.merge(%{raw_image_path: "/images/cover.jpg"}, image_attrs)
            )
          )
        end)
      end

      alt = with_image.(%{alt_text: "Crowd at the hall", title: "Cover"})
      title_only = with_image.(%{alt_text: "", title: "Cover"})
      neither = with_image.(%{alt_text: nil, title: nil})

      refute alt == title_only
      refute title_only == neither

      assert alt ==
               with_image.(%{alt_text: "Crowd at the hall", title: "Other"})
    end

    test "alt falls back to the event title, then a generic label" do
      assigns = poster_assigns()
      image = struct!(Image, raw_image_path: "/images/cover.jpg")

      titled =
        hash_with(assigns, fn event -> Map.put(event, :image, image) end)

      untitled =
        hash_with(assigns, fn event ->
          event |> Map.put(:image, image) |> Map.put(:title, nil)
        end)

      refute titled == untitled
    end

    test "uses a default pricing label when the event has no display text" do
      assigns = poster_assigns()

      no_pricing =
        hash_with(assigns, fn event -> Map.put(event, :pricing_info, nil) end)

      non_binary_text =
        hash_with(assigns, fn event ->
          Map.put(event, :pricing_info, %{display_text: nil})
        end)

      assert no_pricing == non_binary_text
      refute no_pricing == TvPosterImage.hash_assigns(assigns)
    end

    test "falls back to the site origin when asset_base_url is not given" do
      assigns = poster_assigns()
      without_base = Map.delete(assigns, :asset_base_url)

      with_origin =
        Map.put(assigns, :asset_base_url, YscWeb.Emails.Helpers.origin() <> "/")

      assert TvPosterImage.hash_assigns(without_base) ==
               TvPosterImage.hash_assigns(with_origin)
    end

    test "does not HEEx-render the capture document" do
      html = TvPosterImage.build_html(poster_assigns())
      hash = TvPosterImage.hash_assigns(poster_assigns())

      assert html =~ "event-tv-poster"
      refute hash == :crypto.hash(:sha256, html) |> Base.encode16(case: :lower)
    end
  end

  describe "hash_html/1" do
    test "hashes the rendered capture document" do
      event =
        event_fixture(%{title: "Html Hash Night"})
        |> then(&Events.get_event_for_tv_poster(&1.id))

      assigns = TvPosterImage.assigns_for_event(event)
      hash = TvPosterImage.hash_html(assigns)

      assert hash =~ ~r/^[0-9a-f]{64}$/
      assert hash == TvPosterImage.hash_html(assigns)

      expected =
        assigns
        |> TvPosterImage.build_html()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      assert hash == expected
      refute hash == TvPosterImage.hash_html(Map.put(assigns, :sold_out, true))
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
