defmodule YscWeb.NavPressFeedbackTest do
  @moduledoc """
  The nav's press feedback is `scale` on `.nav-link:active`, which does nothing
  to `display: inline` elements. Every nav link must be a transformable box.
  """
  use YscWeb.ConnCase, async: true

  @transformable ~w(block inline-block inline-flex flex)

  test "every nav link can be scaled on press", %{conn: conn} do
    doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    links = doc |> LazyHTML.query("header a.nav-link") |> Enum.to_list()
    assert length(links) >= 8

    for link <- links do
      classes = link |> LazyHTML.attribute("class") |> hd() |> String.split()

      assert Enum.any?(classes, &(&1 in @transformable)),
             "nav link is display:inline and cannot show press feedback: #{LazyHTML.text(link)}"
    end
  end
end
