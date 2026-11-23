defmodule YscWeb.PublicPageTitlesTest do
  @moduledoc """
  Public text pages open with one shared title treatment, `page_masthead/1`,
  so the site reads as one place. (The cabin pages keep their own photo hero.)
  """
  use YscWeb.ConnCase, async: true

  @masthead_pages [
    {"/board", "board-page", "board-masthead", "Board of Directors"},
    {"/choir", "choir-page", "choir-masthead", "YSC Choir"},
    {"/bylaws", "bylaws-page", "bylaws-masthead", "Bylaws"},
    {"/privacy-policy", "privacy-policy-page", "privacy-policy-masthead",
     "Privacy Policy"},
    {"/terms-of-service", "terms-of-service-page", "terms-of-service-masthead",
     "Terms of Service"},
    {"/code-of-conduct", "code-of-conduct-page", "code-of-conduct-masthead",
     "Non-Discrimination Code of Conduct"},
    {"/volunteer", "volunteer-page", "volunteer-masthead",
     "Volunteer with the YSC"},
    {"/contact", "contact-page", "contact-masthead", "Get in touch"}
  ]

  for {path, page_id, id, title} <- @masthead_pages do
    test "#{path} opens with a masthead and a single h1", %{conn: conn} do
      conn = get(conn, unquote(path))
      doc = conn |> html_response(200) |> LazyHTML.from_document()

      assert [_] = doc |> LazyHTML.query("h1") |> Enum.to_list()

      page = LazyHTML.query(doc, "##{unquote(page_id)}")
      assert [_] = Enum.to_list(page)

      masthead = LazyHTML.query(doc, "##{unquote(id)}")
      assert [_] = Enum.to_list(masthead)
      assert LazyHTML.text(masthead) =~ unquote(title)
      assert masthead |> LazyHTML.query("h1") |> Enum.to_list() |> length() == 1
      assert masthead |> LazyHTML.query(".type-eyebrow") |> Enum.to_list() != []
    end
  end

  for {path, text} <- [
        {"/news", "Club News"},
        {"/newsletters", "Newsletters"},
        {"/events", "Calendar"},
        {"/history", "Years"}
      ] do
    test "#{path} hub page uses the default masthead", %{conn: conn} do
      conn = get(conn, unquote(path))
      doc = conn |> html_response(200) |> LazyHTML.from_document()

      assert [h1] = doc |> LazyHTML.query("h1") |> Enum.to_list()
      assert LazyHTML.text(h1) =~ unquote(text)
      assert LazyHTML.attribute(h1, "class") |> hd() =~ "md:text-7xl"
    end
  end
end
