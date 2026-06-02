defmodule Ysc.Events.TvPosterImage.ErrorStub do
  @moduledoc false

  @behaviour Ysc.Events.TvPosterImage.Capture

  @impl true
  def capture_html(_html, _opts), do: {:error, :chrome_unavailable}
end
