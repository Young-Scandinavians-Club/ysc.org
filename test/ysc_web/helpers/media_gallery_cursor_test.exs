defmodule YscWeb.MediaGalleryCursorTest do
  use ExUnit.Case, async: true

  alias YscWeb.MediaGalleryCursor

  describe "assign_cursor_from_images/2" do
    test "clears cursor assigns for an empty page" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          last_image_date: ~U[2024-01-01 00:00:00Z],
          last_image_id: 1
        }
      }

      updated = MediaGalleryCursor.assign_cursor_from_images(socket, [])

      assert updated.assigns.last_image_date == nil
      assert updated.assigns.last_image_id == nil
    end

    test "sets cursor from the last image in the page" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      inserted_at = ~U[2024-06-15 12:00:00Z]

      updated =
        MediaGalleryCursor.assign_cursor_from_images(socket, [
          %{id: 10, inserted_at: ~U[2024-06-16 00:00:00Z]},
          %{id: 11, inserted_at: inserted_at}
        ])

      assert updated.assigns.last_image_date == inserted_at
      assert updated.assigns.last_image_id == 11
    end
  end

  describe "cursor_opts_from_assigns/2" do
    test "returns base opts when cursor date is nil" do
      base = [limit: 30, search: "party"]

      assert MediaGalleryCursor.cursor_opts_from_assigns(base, %{
               last_image_date: nil
             }) ==
               base
    end

    test "adds before_date and before_id when year is not selected" do
      date = ~U[2024-03-01 00:00:00Z]

      opts =
        MediaGalleryCursor.cursor_opts_from_assigns([limit: 30], %{
          last_image_date: date,
          last_image_id: 42,
          selected_year: nil
        })

      assert opts[:limit] == 30
      assert opts[:before_date] == date
      assert opts[:before_id] == 42
    end

    test "adds before_date only when year is nil and id is missing" do
      date = ~U[2024-03-01 00:00:00Z]

      opts =
        MediaGalleryCursor.cursor_opts_from_assigns([limit: 30], %{
          last_image_date: date,
          selected_year: nil
        })

      assert opts[:limit] == 30
      assert opts[:before_date] == date
      refute Keyword.has_key?(opts, :before_id)
    end

    test "includes start_at_year when filtering by year" do
      date = ~U[2024-03-01 00:00:00Z]

      opts =
        MediaGalleryCursor.cursor_opts_from_assigns([limit: 30], %{
          last_image_date: date,
          last_image_id: 7,
          selected_year: 2024
        })

      assert opts[:limit] == 30
      assert opts[:before_date] == date
      assert opts[:before_id] == 7
      assert opts[:start_at_year] == 2024
    end

    test "includes start_at_year without before_id when id is nil" do
      date = ~U[2024-03-01 00:00:00Z]

      opts =
        MediaGalleryCursor.cursor_opts_from_assigns([limit: 30], %{
          last_image_date: date,
          selected_year: 2023
        })

      assert opts[:limit] == 30
      assert opts[:before_date] == date
      assert opts[:start_at_year] == 2023
      refute Keyword.has_key?(opts, :before_id)
    end
  end
end
