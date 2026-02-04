defmodule Ysc.Media.Timeline do
  @moduledoc """
  Timeline utilities for injecting date headers into image streams.
  """

  # A simple struct for our headers
  defmodule Header do
    @moduledoc """
    Represents a date header in the timeline.
    """
    defstruct [:id, :date, :formatted_date, type: :header]
  end

  @doc """
  Injects date headers into a list of images, grouping by year-month.

  Returns a list of mixed %Image{} and %Header{} structs.
  """
  def inject_date_headers(images) when is_list(images) do
    images
    # 1. Group by Year-Month
    |> Enum.chunk_by(fn image ->
      {image.inserted_at.year, image.inserted_at.month}
    end)
    # 2. Flatten back into a list, prepending a Header to each group
    |> Enum.flat_map(fn group ->
      first_image = hd(group)

      header = %Header{
        # Deterministic ID is crucial for Streams!
        id:
          "header-#{first_image.inserted_at.year}-#{first_image.inserted_at.month}",
        date: first_image.inserted_at,
        formatted_date: format_date(first_image.inserted_at)
      }

      [header | group]
    end)
  end

  defp format_date(datetime) do
    # Format as "January 2024"
    Calendar.strftime(datetime, "%B %Y")
  end
end
