defmodule Ysc.GooglePhotos.PosterAlbums do
  @moduledoc """
  Keeps Google Photos albums filled with posters for upcoming events: a display
  album per cabin (shown on the Roku TVs) and a generic "Upcoming YSC Events"
  album for markets, conferences and other displays. Every album gets the same
  posters.

  This is strictly best-effort. Nothing here may affect saving events or any
  page: failures are logged as warnings (never reported as errors) and the
  hourly cron simply tries again.

  `sync/1` reconciles each album against the events that should be on screen:

    * a published event that has not ended gets its poster added;
    * when the rendered poster changes (title, date, sold out, ...) the new
      poster is added and the old one removed;
    * when an event ends, is cancelled, unpublished or deleted, its poster is
      removed.

  Only media items recorded in `google_photos_poster_items` are ever removed, so
  photos added to the album by hand stay in it.
  """

  import Ecto.Query

  require Ysc.Logging

  alias Ysc.Ci.QueryExplain.Fixtures
  alias Ysc.Events
  alias Ysc.Events.TvPosterImage
  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.Api
  alias Ysc.GooglePhotos.PosterAlbum
  alias Ysc.GooglePhotos.PosterItem
  alias Ysc.Repo

  @poster_format "png"

  # Namespace for the two-arg pg_advisory_lock that keeps syncs from running on
  # more than one node at once. Arbitrary; unique among the app's advisory locks.
  @sync_lock_namespace 8_233_101
  @sync_lock_key 1

  @album_titles %{
    tahoe: "Tahoe Display Album",
    clear_lake: "Clear Lake Display Album",
    upcoming: "Upcoming YSC Events"
  }

  @doc "Title of the Google Photos album for an album key."
  def album_title(key) when is_map_key(@album_titles, key),
    do: Map.fetch!(@album_titles, key)

  @doc "Returns true when an event already has a poster in any album."
  def has_items?(event_id) do
    Repo.exists?(from i in PosterItem, where: i.event_id == ^event_id)
  end

  @doc """
  Reconciles every album with the current set of upcoming events.

  Safe to run repeatedly: already-synced posters are skipped, and progress is
  persisted after every upload so a retry never re-uploads finished work.

  Options: `:access_token` overrides the stored Google credentials (tests).

  Returns `{:ok, summary}` with counts, or `{:error, reason}` when Google
  credentials are unavailable or any album/poster could not be synced.
  """
  def sync(opts \\ []) do
    Ysc.Logging.quiet(fn ->
      try do
        with_sync_lock(fn -> do_sync(opts) end)
      rescue
        error -> {:error, {:exception, Exception.message(error)}}
      catch
        kind, reason -> {:error, {kind, inspect(reason)}}
      end
    end)
  end

  # The Oban queue only serializes syncs per node, but two syncs racing on the
  # same event would upload it twice and lose track of one copy. A session-level
  # advisory lock makes the sync single-flight across nodes. A busy lock just
  # skips this run; the next event change or hourly run catches up.
  #
  # Production holds that lock on a *separate* checked-out connection so Chromic
  # PNG capture and Google Photos HTTP do not occupy a Repo pool slot (sync can
  # run for minutes). The SQL sandbox has only the test's connection, so tests
  # keep the lock on the caller checkout.
  defp with_sync_lock(fun) do
    if sandbox_pool?() do
      Repo.checkout(fn -> lock_and_run(fun) end)
    else
      with_detached_lock(fun)
    end
  end

  defp sandbox_pool? do
    Repo.config()[:pool] == Ecto.Adapters.SQL.Sandbox
  end

  defp with_detached_lock(fun) do
    parent = self()
    token = make_ref()

    {:ok, holder} =
      Task.start_link(fn ->
        Repo.checkout(fn ->
          if try_sync_lock?() do
            send(parent, {:sync_lock, token, :acquired})

            receive do
              {:sync_lock, ^token, :release} -> release_sync_lock()
            end
          else
            send(parent, {:sync_lock, token, :busy})
          end
        end)
      end)

    receive do
      {:sync_lock, ^token, :acquired} ->
        try do
          fun.()
        after
          send(holder, {:sync_lock, token, :release})
          await_lock_holder(holder)
        end

      {:sync_lock, ^token, :busy} ->
        busy_lock_result()
    after
      15_000 ->
        Process.unlink(holder)
        Process.exit(holder, :kill)
        {:error, :lock_timeout}
    end
  end

  defp lock_and_run(fun) do
    if try_sync_lock?() do
      try do
        fun.()
      after
        release_sync_lock()
      end
    else
      busy_lock_result()
    end
  end

  defp busy_lock_result do
    Ysc.Logging.info("Google Photos poster sync already running; skipping")
    {:ok, %{published: 0, removed: 0}}
  end

  defp await_lock_holder(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      5_000 ->
        Process.unlink(pid)
        Process.exit(pid, :kill)
        :ok
    end
  end

  defp try_sync_lock? do
    %{rows: [[locked?]]} =
      Repo.query!("SELECT pg_try_advisory_lock($1, $2)", [
        @sync_lock_namespace,
        @sync_lock_key
      ])

    locked?
  end

  defp release_sync_lock do
    Repo.query!("SELECT pg_advisory_unlock($1, $2)", [
      @sync_lock_namespace,
      @sync_lock_key
    ])
  end

  defp do_sync(opts) do
    with {:ok, access_token} <- access_token(opts) do
      desired =
        Map.new(Events.list_tv_poster_events(), fn event ->
          {event.id, %{event: event, hash: poster_hash(event)}}
        end)

      items_by_key =
        PosterItem |> Repo.all() |> Enum.group_by(& &1.key)

      {results, _captures} =
        Enum.map_reduce(PosterAlbum.keys(), %{}, fn key, captures ->
          items = Map.get(items_by_key, key, [])
          sync_album(access_token, key, desired, items, captures)
        end)

      summarize(results)
    end
  end

  defp access_token(opts) do
    case Keyword.fetch(opts, :access_token) do
      {:ok, token} -> {:ok, token}
      :error -> GooglePhotos.get_access_token()
    end
  end

  defp sync_album(access_token, key, desired, items, captures) do
    case ensure_album(access_token, key) do
      {:ok, album_id} ->
        items_by_event = Map.new(items, &{&1.event_id, &1})

        {removed, remove_errors} =
          items
          |> Enum.reject(&Map.has_key?(desired, &1.event_id))
          |> Enum.map(&remove_item(access_token, &1))
          |> split_results()

        {published, publish_errors, captures} =
          desired
          |> Map.values()
          |> Enum.reject(
            &up_to_date?(&1, items_by_event[&1.event.id], album_id)
          )
          |> Enum.reduce({0, [], captures}, fn entry, {ok, errors, captures} ->
            case publish_poster(
                   access_token,
                   key,
                   album_id,
                   entry,
                   items_by_event[entry.event.id],
                   captures
                 ) do
              {:ok, captures} -> {ok + 1, errors, captures}
              {{:error, reason}, captures} -> {ok, [reason | errors], captures}
            end
          end)

        {%{
           key: key,
           published: published,
           removed: removed,
           errors: remove_errors ++ publish_errors
         }, captures}

      {:error, reason} ->
        {%{key: key, published: 0, removed: 0, errors: [reason]}, captures}
    end
  end

  defp summarize(results) do
    errors = Enum.flat_map(results, & &1.errors)

    if errors == [] do
      {:ok,
       %{
         published: results |> Enum.map(& &1.published) |> Enum.sum(),
         removed: results |> Enum.map(& &1.removed) |> Enum.sum()
       }}
    else
      {:error, {:sync_failed, errors}}
    end
  end

  defp split_results(results) do
    {Enum.count(results, &(&1 == :ok)),
     for({:error, reason} <- results, do: reason)}
  end

  defp up_to_date?(
         %{hash: hash},
         %PosterItem{poster_hash: hash, google_album_id: album_id},
         album_id
       ),
       do: true

  # Rows stored before this change hashed the HEEx document. If that HTML
  # hash still matches, rewrite it to the input fingerprint and skip capture.
  defp up_to_date?(%{hash: hash, event: event}, %PosterItem{} = item, album_id) do
    if item.google_album_id == album_id and
         item.poster_hash == html_poster_hash(event) do
      item
      |> PosterItem.changeset(%{poster_hash: hash})
      |> Repo.update()

      true
    else
      false
    end
  end

  defp up_to_date?(_entry, _item, _album_id), do: false

  defp html_poster_hash(event) do
    event
    |> TvPosterImage.assigns_for_event()
    |> TvPosterImage.hash_html()
  end

  # Fingerprint of the values the poster shows (title, date, price, sold out,
  # cover path, ...), plus the poster template sources. Unchanged posters are
  # never re-captured or re-uploaded, and sync does not HEEx-render every
  # upcoming event just to decide that.
  defp poster_hash(event), do: TvPosterImage.hash_event(event)

  defp ensure_album(access_token, key) do
    case Repo.get_by(PosterAlbum, key: key) do
      %PosterAlbum{google_album_id: album_id} ->
        {:ok, album_id}

      nil ->
        title = album_title(key)

        with {:ok, album_id} <- find_or_create_album(access_token, title) do
          # Queue concurrency is 1, but stay safe if two syncs ever overlap.
          %PosterAlbum{}
          |> PosterAlbum.changeset(%{
            key: key,
            google_album_id: album_id
          })
          |> Repo.insert(on_conflict: :nothing, conflict_target: :key)

          {:ok, Repo.get_by!(PosterAlbum, key: key).google_album_id}
        end
    end
  end

  # An album we created earlier may exist even though our record of it was lost
  # (e.g. a restored database), so look it up by title before creating another.
  defp find_or_create_album(access_token, title) do
    with {:ok, albums} <- Api.list_albums(access_token) do
      case Enum.find(albums, &(&1["title"] == title)) do
        %{"id" => album_id} -> {:ok, album_id}
        nil -> Api.create_album(access_token, title)
      end
    end
  end

  # Adds the new poster before removing the old one so the album never has a
  # gap while a poster is being replaced.
  defp publish_poster(access_token, key, album_id, entry, item, captures) do
    %{event: event, hash: hash} = entry
    filename = TvPosterImage.filename(event, @poster_format)

    {capture, captures} = capture_poster(captures, event)

    result =
      with {:ok, bytes} <- capture,
           {:ok, upload_token} <-
             Api.upload_bytes(access_token, bytes, filename, event.id),
           {:ok, media_item} <-
             Api.create_media_item(
               access_token,
               upload_token,
               album_id,
               filename
             ),
           {:ok, new_item} <-
             save_item(event, key, album_id, media_item["id"], hash) do
        discard_replaced_media(access_token, item, new_item)
        :ok
      end

    case result do
      :ok ->
        {:ok, captures}

      {:error, reason} ->
        Ysc.Logging.warning("TV poster Google Photos upload failed",
          event_id: event.id,
          key: key,
          error: inspect(reason)
        )

        {{:error, reason}, captures}
    end
  end

  # The same image is used for every album, so capture each event once.
  defp capture_poster(captures, event) do
    case Map.fetch(captures, event.id) do
      {:ok, result} ->
        {result, captures}

      :error ->
        result =
          event
          |> TvPosterImage.assigns_for_event()
          |> TvPosterImage.capture(format: @poster_format)

        {result, Map.put(captures, event.id, result)}
    end
  end

  defp save_item(event, key, album_id, media_item_id, hash)
       when is_binary(media_item_id) do
    %PosterItem{}
    |> PosterItem.changeset(%{
      event_id: event.id,
      key: key,
      google_album_id: album_id,
      media_item_id: media_item_id,
      poster_hash: hash
    })
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:google_album_id, :media_item_id, :poster_hash, :updated_at]},
      conflict_target: [:event_id, :key],
      returning: true
    )
  end

  defp save_item(_event, _property, _album_id, _media_item_id, _hash),
    do: {:error, :missing_media_item_id}

  defp discard_replaced_media(_access_token, nil, _new_item), do: :ok

  defp discard_replaced_media(access_token, %PosterItem{} = old, new_item) do
    if old.media_item_id != new_item.media_item_id do
      case Api.remove_media_items(access_token, old.google_album_id, [
             old.media_item_id
           ]) do
        :ok ->
          :ok

        {:error, reason} ->
          Ysc.Logging.warning(
            "Could not remove replaced TV poster from Google Photos album",
            event_id: old.event_id,
            key: old.key,
            error: inspect(reason)
          )

          :ok
      end
    else
      :ok
    end
  end

  # 400/404 mean Google no longer has the item in that album (removed by hand,
  # or the album is gone), which is the state we want, so drop our record too.
  defp remove_item(access_token, %PosterItem{} = item) do
    result =
      Api.remove_media_items(access_token, item.google_album_id, [
        item.media_item_id
      ])

    if result == :ok or gone?(result) do
      Repo.delete(item)
      :ok
    else
      Ysc.Logging.warning("TV poster removal from Google Photos failed",
        event_id: item.event_id,
        key: item.key,
        error: inspect(result)
      )

      result
    end
  end

  defp gone?({:error, {:api_error, status}}) when status in [400, 404],
    do: true

  defp gone?(_), do: false

  @doc false
  def ci_query_explain_query do
    event_id = Fixtures.ulid()

    from(i in PosterItem, where: i.event_id == ^event_id)
  end
end
