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

  defmodule Section do
    @moduledoc """
    A year-month group with a sticky header and its images.

    Used as a LiveView stream item so headers can sit outside masonry columns.
    """
    defstruct [:id, :header, :images, type: :section]
  end

  @doc """
  Groups images into year-month sections for gallery rendering.

  Each section has a sticky-friendly header outside the masonry grid.
  """
  def inject_sections(images) when is_list(images) do
    images
    |> Enum.chunk_by(fn image ->
      {image.inserted_at.year, image.inserted_at.month}
    end)
    |> Enum.map(&section_from_image_group/1)
  end

  @doc """
  Appends images to the last section when load-more stays in the same month.
  """
  def append_images_to_last_section(sections, images)
      when is_list(sections) and is_list(images) do
    case List.last(sections) do
      %Section{} = last ->
        List.replace_at(sections, -1, %{last | images: last.images ++ images})

      _ ->
        sections ++ inject_sections(images)
    end
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

  defp section_from_image_group([%_{inserted_at: inserted_at} | _] = group) do
    header = %Header{
      id: "header-#{inserted_at.year}-#{inserted_at.month}",
      date: inserted_at,
      formatted_date: format_date(inserted_at)
    }

    %Section{
      id: "section-#{inserted_at.year}-#{inserted_at.month}",
      header: header,
      images: group
    }
  end

  defp format_date(datetime) do
    # Format as "January 2024"
    Calendar.strftime(datetime, "%B %Y")
  end
end
