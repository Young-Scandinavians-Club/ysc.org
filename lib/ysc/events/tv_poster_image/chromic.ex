defmodule Ysc.Events.TvPosterImage.Chromic do
  @moduledoc false

  require Ysc.Logging

  alias Ysc.Events.TvPosterImage

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
           capture_screenshot: %{
             format: format,
             clip: %{x: 0, y: 0, width: width, height: height, scale: 1}
           },
           wait_for: %{selector: "#event-tv-poster"},
           timeout: 30_000
         ) do
      {:ok, base64} when is_binary(base64) ->
        {:ok, Base.decode64!(base64)}

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
