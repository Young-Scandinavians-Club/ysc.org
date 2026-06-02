defmodule Ysc.Events.TvPosterImage.Chromic do
  @moduledoc false

  require Ysc.Logging

  alias Ysc.Events.TvPosterImage

  # ChromicPDF runs this before capture; a returned Promise is awaited.
  @wait_for_poster_ready """
  (async () => {
    const poster = document.querySelector("#event-tv-poster");
    if (!poster) throw new Error("TV poster element not found");

    const images = poster.querySelectorAll("img");
    await Promise.all(
      Array.from(images).map((img) => {
        if (img.complete) return;
        return new Promise((resolve) => {
          img.addEventListener("load", resolve, { once: true });
          img.addEventListener("error", resolve, { once: true });
        });
      })
    );

    if (document.fonts && document.fonts.ready) {
      await document.fonts.ready;
    }
  })()
  """

  @behaviour Ysc.Events.TvPosterImage.Capture

  @impl true
  def capture_html(html, opts) do
    format = TvPosterImage.normalize_format(Keyword.get(opts, :format, "png"))
    {width, height} = TvPosterImage.dimensions()

    capture(format, width, height, html)
  end

  defp capture(format, width, height, html) do
    case ChromicPDF.capture_screenshot(
           {:html, html},
           # Match viewport to the 1920×1080 poster; clip alone leaves most of the frame black.
           full_page: true,
           capture_screenshot: %{
             format: format,
             clip: %{x: 0, y: 0, width: width, height: height, scale: 1},
             captureBeyondViewport: true
           },
           evaluate: %{expression: @wait_for_poster_ready},
           timeout: 30_000
         ) do
      {:ok, base64} when is_binary(base64) ->
        case Base.decode64(base64) do
          {:ok, binary} ->
            {:ok, binary}

          :error ->
            Ysc.Logging.error(
              "TV poster ChromicPDF capture returned invalid base64",
              extra: %{format: format}
            )

            {:error, :invalid_base64}
        end

      other ->
        Ysc.Logging.error("TV poster ChromicPDF capture failed",
          extra: %{result: inspect(other), format: format}
        )

        {:error, other}
    end
  rescue
    error in ChromicPDF.ChromeError ->
      Ysc.Logging.error("TV poster ChromicPDF capture failed",
        error: error,
        stacktrace: __STACKTRACE__,
        extra: %{format: format}
      )

      {:error, error}
  end
end
