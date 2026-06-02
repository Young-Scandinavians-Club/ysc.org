defmodule Ysc.Events.TvPosterImage.Capture do
  @moduledoc false

  @callback capture_html(String.t(), keyword()) ::
              {:ok, binary()} | {:error, term()}
end
