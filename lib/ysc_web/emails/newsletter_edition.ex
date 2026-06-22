defmodule YscWeb.Emails.NewsletterEdition do
  @moduledoc """
  Email template for newsletter editions (curated: cover, intro, posts, events).
  """
  alias Ysc.Events
  alias Ysc.Media.Image
  alias HtmlSanitizeEx

  use MjmlEEx,
    mjml_template: "templates/newsletter_edition.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [absolute_url: 1]

  @doc """
  Transforms Trix editor HTML into email-safe HTML for use inside MJML mj-text blocks.

  Trix produces HTML with `<figure>` wrappers, `data-trix-*` attributes, and class names
  that reference Trix's own CSS — none of which renders correctly in email clients.

  Transformations applied:
    - Trix figure attachments (`<figure><a><img><figcaption>`) → `<img>` with inline styles
      plus an optional styled caption `<p>`.
    - All `data-trix-*` attributes stripped.
    - All `class` attributes stripped (Trix CSS is not present in email clients).
    - Standard formatting tags (`em`, `strong`, `a`, `br`, `ul`, `ol`, `li`, etc.) kept as-is.
  """
  def email_safe_html(nil), do: ""
  def email_safe_html(""), do: ""

  def email_safe_html(html) when is_binary(html) do
    case String.trim(html) do
      "" ->
        ""

      trimmed ->
        trimmed
        |> Floki.parse_fragment!()
        |> transform_nodes_for_email()
        |> Floki.raw_html()
    end
  end

  defp transform_nodes_for_email(nodes) do
    Enum.flat_map(nodes, &transform_node_for_email/1)
  end

  # Convert Trix figure attachments to email-safe HTML.
  #
  # Image attachments → <img> + optional styled caption <p>.
  # Non-image file attachments → styled download link <a> inside a <p>.
  defp transform_node_for_email({"figure", _attrs, children}) do
    fragment = [{"figure", [], children}]

    case Floki.find(fragment, "img") do
      [{"img", img_attrs, _} | _] ->
        src = floki_attr(img_attrs, "src")
        alt = floki_attr(img_attrs, "alt") || ""

        img_nodes =
          if src do
            [
              {"img",
               [
                 {"src", src},
                 {"alt", alt},
                 {"style",
                  "max-width:100%;height:auto;display:block;margin:8px auto;border-radius:4px;"}
               ], []}
            ]
          else
            []
          end

        caption_nodes =
          case Floki.find(fragment, "figcaption") do
            [cap | _] ->
              text = cap |> Floki.text() |> String.trim()

              if text != "" do
                [
                  {"p",
                   [
                     {"style",
                      "text-align:center;font-size:12px;color:#666666;font-style:italic;margin:4px 0 12px 0;"}
                   ], [text]}
                ]
              else
                []
              end

            _ ->
              []
          end

        img_nodes ++ caption_nodes

      _ ->
        # Non-image file attachment — render as a download link button
        href =
          case Floki.find(fragment, "a") do
            [{"a", a_attrs, _} | _] -> floki_attr(a_attrs, "href")
            _ -> nil
          end

        filename =
          case Floki.find(fragment, ".attachment__name") do
            [node | _] -> node |> Floki.text() |> String.trim()
            _ -> nil
          end

        filesize =
          case Floki.find(fragment, ".attachment__size") do
            [node | _] -> node |> Floki.text() |> String.trim()
            _ -> nil
          end

        label =
          case {filename, filesize} do
            {nil, _} -> "Download file"
            {name, nil} -> name
            {name, size} -> "#{name} (#{size})"
          end

        if href do
          [
            {"p", [{"style", "margin:8px 0 16px 0;"}],
             [
               {"a",
                [
                  {"href", href},
                  {"style",
                   "display:inline-block;padding:8px 14px;background-color:#f5f5f5;border:1px solid #dddddd;border-radius:4px;text-decoration:none;color:#333333;font-size:14px;font-family:Arial,Helvetica,sans-serif;"}
                ], [label]}
             ]}
          ]
        else
          if filename, do: [{"p", [], [label]}], else: []
        end
    end
  end

  # Trix serializes every paragraph as a <div>. Convert these to <p> elements
  # so that email clients render paragraph spacing correctly. <br>-only blocks
  # (Trix's empty-line representation) are dropped to avoid spurious blank lines.
  defp transform_node_for_email({"div", _attrs, children}) do
    inner = transform_nodes_for_email(children)

    case inner do
      # <div><br></div> — Trix empty-block placeholder; emit a spacing <br>
      [{"br", _, _}] -> [{"br", [], []}]
      # All other div blocks → <p>
      _ -> [{"p", [], inner}]
    end
  end

  # Strip data-trix-* and class attrs from all other tags, recurse into children
  defp transform_node_for_email({tag, attrs, children}) do
    safe_attrs =
      Enum.reject(attrs, fn {name, _} ->
        String.starts_with?(name, "data-trix") or name == "class"
      end)

    [{tag, safe_attrs, transform_nodes_for_email(children)}]
  end

  defp transform_node_for_email(text) when is_binary(text), do: [text]

  defp floki_attr(attrs, name) do
    case Enum.find(attrs, fn {k, _} -> k == name end) do
      {_, v} -> v
      nil -> nil
    end
  end

  def get_template_name do
    "newsletter_edition"
  end

  def present_unsubscribe_url?(url)
  def present_unsubscribe_url?(nil), do: false
  def present_unsubscribe_url?(""), do: false
  def present_unsubscribe_url?("#"), do: false
  def present_unsubscribe_url?(_url), do: true

  @doc """
  Builds the assign map for the newsletter edition template.

  Use with `NewsletterEdition.render(NewsletterEdition.build_assigns(edition, subscriber, posts, events))`.
  """
  # intro_html is produced by email_safe_html/1 which strips all attributes and
  # unknown tags via Floki; content is admin-authored only.
  # sobelow_skip ["XSS.Raw"]
  def build_assigns(edition, subscriber, posts, events) do
    first_name = subscriber.first_name || "there"

    unsubscribe_url =
      (subscriber.subscription_token &&
         absolute_url(
           "/newsletter/unsubscribe/" <> subscriber.subscription_token
         )) || "#"

    intro_html = email_safe_html(edition.intro_text)

    %{
      first_name: first_name,
      edition_title: edition.title,
      intro_text: Phoenix.HTML.raw(intro_html),
      intro_text?: intro_html != "",
      cover_image_url: cover_image_url(edition),
      posts: Enum.map(posts, &post_render_map/1),
      events: Enum.map(events, &event_render_map/1),
      unsubscribe_url: unsubscribe_url
    }
  end

  @doc """
  Builds assigns for archiving a sent edition (no subscriber context).

  Produces the same output as `build_preview_assigns/5` but accepts the full
  edition struct (with `:cover_image` preloaded) so callers don't need to
  extract the cover URL themselves.
  """
  def build_archive_assigns(edition, posts, events) do
    build_preview_assigns(
      edition.title,
      edition.intro_text,
      cover_image_url(edition),
      posts,
      events
    )
  end

  @doc """
  Builds assigns for the admin editor preview (full email as recipients see it).

  Uses a placeholder subscriber so first_name is "there" and unsubscribe_url points
  to the public unsubscribe page (recipients get their own link in the real email).
  """
  # intro_html is produced by email_safe_html/1 which strips all attributes and
  # unknown tags via Floki; content is admin-authored only.
  # sobelow_skip ["XSS.Raw"]
  def build_preview_assigns(title, intro_text, cover_image_url, posts, events) do
    intro_html = email_safe_html(intro_text)

    %{
      first_name: "there",
      edition_title: title,
      intro_text: Phoenix.HTML.raw(intro_html),
      intro_text?: intro_html != "",
      cover_image_url: cover_image_url,
      posts: Enum.map(posts, &post_render_map/1),
      events: Enum.map(events, &event_render_map/1),
      unsubscribe_url: "/newsletter/unsubscribe/preview"
    }
  end

  defp cover_image_url(%{cover_image: nil}), do: nil
  defp cover_image_url(%{cover_image: img}), do: Image.display_path(img)

  defp post_render_map(post) do
    %{
      title: post.title,
      preview_text:
        clean_preview_text(post.preview_text || post.raw_body || ""),
      url: absolute_url("/posts/#{post.url_name}"),
      image_url: post_image_url(post.featured_image)
    }
  end

  defp clean_preview_text(""), do: ""

  defp clean_preview_text(text) do
    text
    |> YscWeb.PlainText.from_html()
    |> String.trim()
    |> then(fn
      "" -> ""
      plain -> String.slice(plain, 0, 200)
    end)
  end

  defp post_image_url(image), do: Image.display_path(image)

  defp event_render_map(event) do
    %{
      title: event.title,
      description:
        event.description && HtmlSanitizeEx.strip_tags(event.description),
      short_description: short_description(event.description),
      date_str: format_event_date(event),
      save_the_date: Map.get(event, :tickets_tbd, false),
      selling_fast: Events.event_selling_fast?(event.id),
      pricing_str: Events.event_pricing_display_string(event),
      tickets_on_sale_str: format_tickets_on_sale(event),
      location_name: event.location_name,
      url: absolute_url("/events/#{event.id}"),
      image_url: event_image_url(event)
    }
  end

  defp short_description(nil), do: nil
  defp short_description(""), do: nil

  defp short_description(desc) when is_binary(desc) do
    desc =
      desc
      |> HtmlSanitizeEx.strip_tags()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    if String.length(desc) <= 140,
      do: desc,
      else: String.slice(desc, 0, 137) <> "..."
  end

  defp format_tickets_on_sale(event) do
    case Events.event_earliest_tickets_sale_date(event) do
      nil -> nil
      dt -> "Tickets on sale #{Calendar.strftime(dt, "%b %d, %Y")}"
    end
  end

  defp event_image_url(%{cover_image: cover_image}),
    do: Image.display_path(cover_image)

  defp format_event_date(event) do
    case {event.start_date, event.start_time} do
      {nil, _} ->
        ""

      {date, nil} ->
        Calendar.strftime(date, "%b %d, %Y")

      {date, time} ->
        "#{Calendar.strftime(date, "%b %d")} at #{Calendar.strftime(time, "%H:%M")}"
    end
  end
end
