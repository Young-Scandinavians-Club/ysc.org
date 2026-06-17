defmodule Ysc.Media.Timeline.Section do
  @moduledoc """
  A year-month group with a sticky header and its images.

  Used as a LiveView stream item so headers can sit outside masonry columns.
  """
  defstruct [:id, :header, :images, type: :section]
end
