defmodule YscWeb.MediaGalleryCursor do
  @moduledoc """
  Cursor pagination helpers for media gallery pickers and admin media views.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ysc.Media

  @doc """
  Fetches a page via `Media.list_images_cursor/1`.

  Returns `{images, end_of_timeline?}` where `end_of_timeline?` is true when
  fewer than `limit` images were returned.
  """
  @spec list_page(keyword()) :: {[map()], boolean()}
  def list_page(opts) do
    limit = Keyword.fetch!(opts, :limit)
    images = Media.list_images_cursor(opts)
    {images, length(images) < limit}
  end

  @doc """
  Updates `last_image_date` and `last_image_id` assigns from a page of images.
  """
  @spec assign_cursor_from_images(Phoenix.LiveView.Socket.t(), [map()]) ::
          Phoenix.LiveView.Socket.t()
  def assign_cursor_from_images(socket, []),
    do: socket |> assign(:last_image_date, nil) |> assign(:last_image_id, nil)

  def assign_cursor_from_images(socket, images) do
    case List.last(images) do
      nil ->
        assign_cursor_from_images(socket, [])

      %{inserted_at: inserted_at, id: id} ->
        socket
        |> assign(:last_image_date, inserted_at)
        |> assign(:last_image_id, id)
    end
  end

  @doc """
  Merges cursor opts (`before_date`, `before_id`, `start_at_year`) from picker
  assigns (`last_image_date`, `last_image_id`, `selected_year`).
  """
  @spec cursor_opts_from_assigns(keyword(), map()) :: keyword()
  def cursor_opts_from_assigns(opts, %{last_image_date: nil}), do: opts

  def cursor_opts_from_assigns(opts, %{
        last_image_date: date,
        last_image_id: id,
        selected_year: nil
      })
      when not is_nil(id) do
    opts
    |> Keyword.put(:before_date, date)
    |> Keyword.put(:before_id, id)
  end

  def cursor_opts_from_assigns(opts, %{last_image_date: date, selected_year: nil}),
    do: Keyword.put(opts, :before_date, date)

  def cursor_opts_from_assigns(opts, %{
        last_image_date: date,
        last_image_id: id,
        selected_year: year
      })
      when not is_nil(year) and not is_nil(id) do
    opts
    |> Keyword.put(:before_date, date)
    |> Keyword.put(:before_id, id)
    |> Keyword.put(:start_at_year, year)
  end

  def cursor_opts_from_assigns(opts, %{last_image_date: date, selected_year: year})
      when not is_nil(year) do
    opts
    |> Keyword.put(:before_date, date)
    |> Keyword.put(:start_at_year, year)
  end

  @doc """
  After fetching a fresh page, updates cursor/end-of-timeline assigns and resets a stream.
  """
  @spec apply_reset_page(
          Phoenix.LiveView.Socket.t(),
          [map()],
          pos_integer(),
          atom()
        ) :: Phoenix.LiveView.Socket.t()
  def apply_reset_page(socket, images, per_page, stream_name) do
    socket
    |> assign(:end_of_timeline?, length(images) < per_page)
    |> assign_cursor_from_images(images)
    |> Phoenix.LiveView.stream(stream_name, images, reset: true)
  end

  @doc """
  After fetching the next page, updates cursor assigns and appends to a stream.
  """
  @spec apply_append_page(Phoenix.LiveView.Socket.t(), [map()], atom()) ::
          Phoenix.LiveView.Socket.t()
  def apply_append_page(socket, images, stream_name) do
    socket
    |> assign_cursor_from_images(images)
    |> Phoenix.LiveView.stream(stream_name, images)
  end
end
