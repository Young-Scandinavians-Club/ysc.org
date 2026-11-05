defmodule Ysc.Media.PosterReview do
  @moduledoc """
  Qualitative review of an event poster (cover) image by a multimodal LLM.

  Complements `Ysc.Media.PosterQuality`, which checks pixel dimensions. This
  checks design rules a pixel count cannot see:

    * `:embedded_text` - flyers or other readable text baked into the image,
      which clashes with the page's own HTML text and gets cropped on mobile
    * `:collage_or_border` - several photos stitched together, or a frame/border
    * `:off_center_subject` - the main subject pushed to the left/right edges,
      which are cropped on narrow screens
    * `:not_a_photograph` - screenshots, clipart, memes, watermarked stock

  The model can be wrong, so findings are advisory: callers show them as soft
  warnings the admin can dismiss. The image is downscaled and sent inline as a
  data URL so it does not need to be publicly reachable by the provider.

  Uses `Ysc.OpenRouter`; returns `{:error, :not_configured}` when no API key is
  set. Set `OPENROUTER_VISION_MODEL` to choose a vision-capable model.
  """

  require Ysc.Logging

  alias Ysc.Http.UrlFetchGuard
  alias Ysc.Media.Image, as: MediaImage
  alias Ysc.OpenRouter

  @rules [
    :embedded_text,
    :collage_or_border,
    :off_center_subject,
    :not_a_photograph
  ]
  @rule_names Map.new(@rules, &{Atom.to_string(&1), &1})

  @default_vision_model "google/gemini-2.5-flash"
  @review_width 1024
  @jpeg_quality 80
  @max_download_bytes 25 * 1024 * 1024
  @max_detail_length 200

  @type finding :: %{rule: atom(), detail: String.t()}

  @system_prompt """
  You are a strict but fair event poster reviewer for a club website. The image
  will be the cover photo of an event, shown in a 16:9 frame behind HTML text
  overlays and cropped on narrow mobile screens.

  Check the image against these rules and report ONLY the rules it clearly
  violates:

  - embedded_text: readable text, event details, dates, prices, or a logo with
    heavy text baked into the image (a digital flyer). Ignore tiny incidental
    text such as signs, shirts or book spines in a real photo.
  - collage_or_border: several photos stitched together, a split screen, or an
    artificial border or frame. A single continuous photographic scene is required.
  - off_center_subject: the main subject (people, venue focal point) sits at the
    far left or right edge, or at the bottom where a title gradient will cover it.
  - not_a_photograph: a screenshot, flat vector clipart, illustration, meme, or
    a stock photo with a visible watermark. It must be an actual photograph.

  When unsure, do not report the rule. Respond with JSON only, no prose, in
  exactly this shape:

  {"findings": [{"rule": "<rule name>", "detail": "<one short sentence>"}]}

  Use {"findings": []} when the image passes every rule.
  """

  @doc "The rules the reviewer checks, in display order."
  def rules, do: @rules

  @doc """
  True when OpenRouter is configured, so callers can skip the review (and any
  \"checking…\" UI) entirely instead of downloading an image for nothing.
  """
  @spec available?() :: boolean()
  def available? do
    case Application.get_env(:ysc, :open_router, [])[:api_key] do
      key when is_binary(key) -> String.trim(key) != ""
      _ -> false
    end
  end

  @doc """
  Human-readable `{title, advice}` for a rule, suitable for an admin callout.
  """
  @spec describe(atom()) :: {String.t(), String.t()}
  def describe(:embedded_text) do
    {"Text in the image",
     "Text baked into the photo clashes with the page's own text and gets " <>
       "cut off on mobile. A clean photo works best."}
  end

  def describe(:collage_or_border) do
    {"Collage or border",
     "Use a single, continuous photo without a frame or stitched-together images."}
  end

  def describe(:off_center_subject) do
    {"Subject near the edge",
     "The edges are cropped on mobile and the bottom sits under the title. " <>
       "Keep the main subject near the center."}
  end

  def describe(:not_a_photograph) do
    {"Doesn't look like a photograph",
     "Screenshots, clipart, memes and watermarked stock photos look out of " <>
       "place. Use a real photo of the venue, activity or gathering."}
  end

  @doc """
  Reviews `image` and returns the rule violations the model found.

  `{:ok, []}` means the image passed. Errors are returned, never raised, so a
  provider outage can't break the editor.
  """
  @spec review(struct()) :: {:ok, [finding()]} | {:error, term()}
  def review(%MediaImage{} = image) do
    with url when is_binary(url) <- MediaImage.display_path(image),
         {:ok, bytes} <- download(url),
         {:ok, data_url} <- to_data_url(bytes),
         {:ok, raw} <- OpenRouter.chat(messages(data_url), model: model()),
         {:ok, findings} <- parse_findings(raw) do
      {:ok, findings}
    else
      nil -> {:error, :no_image_path}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Downscales image bytes to #{@review_width}px on the longest side and encodes
  them as a JPEG data URL. Keeps the request small and cheap while leaving
  enough detail to spot text.
  """
  @spec to_data_url(binary()) :: {:ok, String.t()} | {:error, :unreadable_image}
  def to_data_url(bytes) when is_binary(bytes) do
    with {:ok, image} <- Image.from_binary(bytes),
         {:ok, small} <- Image.thumbnail(image, @review_width, resize: :down),
         {:ok, jpeg} <-
           Image.write(small, :memory, suffix: ".jpg", quality: @jpeg_quality) do
      {:ok, "data:image/jpeg;base64," <> Base.encode64(jpeg)}
    else
      _ -> {:error, :unreadable_image}
    end
  end

  @doc """
  Parses the model's reply into findings, tolerating code fences and ignoring
  unknown rules. Returns `{:error, :invalid_response}` when it isn't usable JSON.
  """
  @spec parse_findings(String.t()) ::
          {:ok, [finding()]} | {:error, :invalid_response}
  def parse_findings(raw) when is_binary(raw) do
    case raw |> strip_code_fence() |> Jason.decode() do
      {:ok, %{"findings" => findings}} when is_list(findings) ->
        {:ok,
         findings
         |> Enum.flat_map(&finding/1)
         |> Enum.uniq_by(& &1.rule)}

      _ ->
        {:error, :invalid_response}
    end
  end

  defp finding(%{"rule" => rule} = entry) when is_binary(rule) do
    case Map.fetch(@rule_names, rule) do
      {:ok, rule} -> [%{rule: rule, detail: detail(entry["detail"])}]
      :error -> []
    end
  end

  defp finding(_), do: []

  defp detail(text) when is_binary(text) do
    text |> String.trim() |> String.slice(0, @max_detail_length)
  end

  defp detail(_), do: ""

  defp messages(data_url) do
    [
      %{role: "system", content: @system_prompt},
      %{
        role: "user",
        content: [
          %{type: "text", text: "Review this event poster image."},
          %{type: "image_url", image_url: %{url: data_url}}
        ]
      }
    ]
  end

  defp model do
    config = Application.get_env(:ysc, :open_router, [])

    case config[:vision_model] do
      model when is_binary(model) and model != "" -> model
      _ -> @default_vision_model
    end
  end

  defp download(url) do
    req_opts =
      [receive_timeout: 20_000, max_redirects: 3, decode_body: false]
      |> Keyword.merge(
        Application.get_env(:ysc, :poster_review_req_options, [])
      )

    with :ok <- validate_url(url),
         {:ok, %Req.Response{status: 200, body: body}}
         when is_binary(body) and byte_size(body) in 1..@max_download_bytes <-
           Req.get(url, req_opts) do
      {:ok, body}
    else
      {:error, reason} ->
        Ysc.Logging.warning("Poster review image download failed",
          url: url,
          error: inspect(reason)
        )

        {:error, :download_failed}

      other ->
        Ysc.Logging.warning("Poster review image download rejected",
          url: url,
          error: inspect(other, limit: 5)
        )

        {:error, :download_failed}
    end
  end

  defp validate_url(url) do
    case UrlFetchGuard.validate_url_for_server_fetch(url) do
      :ok -> :ok
      {:error, _reason} -> {:error, :blocked_url}
    end
  end

  defp strip_code_fence(raw) do
    raw
    |> String.trim()
    |> String.replace_prefix("```json", "")
    |> String.replace_prefix("```", "")
    |> String.trim_trailing("```")
    |> String.trim()
  end
end
