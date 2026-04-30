defmodule YscWeb.PageHTMLTest do
  @moduledoc """
  Exercises `YscWeb.PageHTML` embedded templates (including `atom_to_readable/1` branches).
  """
  use ExUnit.Case, async: true

  defp rendered_to_binary(%Phoenix.LiveView.Rendered{} = r) do
    r |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
  end

  describe "board/1" do
    test "renders HTML with string board_position (binary atom_to_readable branch)" do
      html =
        YscWeb.PageHTML.board(%{
          bod_members: [
            %{
              first_name: "T",
              last_name: "U",
              email: "t@example.com",
              id: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
              most_connected_country: "US",
              board_position: "vice_president"
            }
          ],
          vacant_positions: MapSet.new([])
        })
        |> rendered_to_binary()

      assert html =~ "Board of Directors"
      assert html =~ "Vice President"
    end

    test "renders HTML with atom board_position" do
      html =
        YscWeb.PageHTML.board(%{
          bod_members: [
            %{
              first_name: "A",
              last_name: "B",
              email: "a@example.com",
              id: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
              most_connected_country: "SE",
              board_position: :secretary
            }
          ],
          vacant_positions: MapSet.new([])
        })
        |> rendered_to_binary()

      assert html =~ "Secretary"
    end

    test "renders board_bio when present and escapes HTML" do
      html =
        YscWeb.PageHTML.board(%{
          bod_members: [
            %{
              first_name: "T",
              last_name: "U",
              email: "t@example.com",
              id: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
              most_connected_country: "US",
              board_position: :president,
              board_bio: "Line one.\n\n<script>x</script>"
            }
          ],
          vacant_positions: MapSet.new([])
        })
        |> rendered_to_binary()

      assert html =~ "Line one."
      assert html =~ "&lt;script&gt;"
      refute html =~ "<script>x</script>"
    end
  end

  describe "contact/1" do
    test "renders static contact page HTML" do
      html = YscWeb.PageHTML.contact(%{}) |> rendered_to_binary()
      assert html =~ "Contact Us"
      assert html =~ "info@ysc.org"
    end
  end
end
