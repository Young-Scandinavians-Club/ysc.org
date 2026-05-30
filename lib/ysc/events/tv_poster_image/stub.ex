defmodule Ysc.Events.TvPosterImage.Stub do
  @moduledoc false

  @behaviour Ysc.Events.TvPosterImage.Capture

  # 1×1 PNG (valid image bytes for controller tests without Chrome)
  @stub_png Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
            )

  @impl true
  def capture_html(_html, _opts), do: {:ok, @stub_png}
end
