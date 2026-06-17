defmodule Ysc.Media.Timeline do
  @moduledoc """
  Timeline utilities for injecting date headers into image streams.
  """

  alias Ysc.Media.Timeline.Header
  alias Ysc.Media.Timeline.Section

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

  Images from other months are grouped into new sections appended after the last
  section.
  """
  def append_images_to_last_section(sections, images)
      when is_list(sections) and is_list(images) do
    case List.last(sections) do
      %Section{header: %Header{date: last_date}} = last ->
        {same_month, other_months} =
          Enum.split_with(images, fn image ->
            image.inserted_at.year == last_date.year &&
              image.inserted_at.month == last_date.month
          end)

        sections =
          if same_month == [] do
            sections
          else
            List.replace_at(sections, -1, %{
              last
              | images: last.images ++ same_month
            })
          end

        if other_months == [] do
          sections
        else
          sections ++ inject_sections(other_months)
        end

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

  defp section_from_image_group([%{inserted_at: inserted_at} | _] = group) do
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
