defmodule YscWeb.Workers.EventPhotoUploadWorkerTest do
  @moduledoc """
  Uses real local MinIO (see `config/test.exs` / CI's "Start MinIO and create
  buckets" step) rather than mocking S3. The worker downloads via a plain
  unsigned HTTP GET against the object's public URL (not a signed ExAws
  GetObject — see the moduledoc on `download_from_s3/2` for why), so a real
  object needs to actually exist at that URL for these tests to mean anything.
  """
  use Ysc.DataCase, async: false

  alias Ysc.EventPhotos
  alias Ysc.S3Config
  alias YscWeb.Workers.EventPhotoUploadWorker

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  @tiny_png Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            )

  setup do
    prev = Application.get_env(:ysc, :google_photos, [])

    Application.put_env(
      :ysc,
      :google_photos,
      Keyword.put(prev, :dev_stub, true)
    )

    on_exit(fn -> Application.put_env(:ysc, :google_photos, prev) end)

    organizer = user_fixture()
    user = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id, state: :published})
    {:ok, collection} = EventPhotos.ensure_collection_for_event(event)

    %{event: event, collection: collection, user: user}
  end

  defp put_s3_object(key, bytes) do
    S3Config.bucket_name()
    |> ExAws.S3.put_object(key, bytes)
    |> ExAws.request!()
  end

  # Mirrors how the worker itself checks: a plain HTTP GET against the public
  # URL. ExAws.S3.get_object/2 against local MinIO is unreliable here — it
  # intermittently issues a POST instead of a GET (an ExAws/Req version
  # quirk), which MinIO rejects; see download_from_s3/2's moduledoc for the
  # same issue affecting the worker's old ExAws-based download path.
  defp s3_object_exists?(key) do
    url = S3Config.object_url(key, S3Config.bucket_name())
    match?({:ok, %{status: 200}}, Req.get(url))
  end

  defp make_job(args, opts \\ []) do
    %Oban.Job{
      id: 1,
      args: args,
      worker: "YscWeb.Workers.EventPhotoUploadWorker",
      queue: "media",
      state: "available",
      attempt: Keyword.get(opts, :attempt, 1),
      max_attempts: Keyword.get(opts, :max_attempts, 5)
    }
  end

  test "downloads from S3 and hands the file off to Google Photos, then deletes the object",
       %{collection: collection, user: user} do
    key = "event_photo_uploads/#{collection.id}/#{Ecto.UUID.generate()}.png"
    put_s3_object(key, @tiny_png)

    job =
      make_job(%{
        "collection_id" => collection.id,
        "s3_key" => key,
        "filename" => "party.png",
        "user_id" => user.id
      })

    assert :ok = EventPhotoUploadWorker.perform(job)
    refute s3_object_exists?(key)

    storage_dir =
      Path.join(Ysc.SafeFile.dev_event_photos_root(), collection.event_id)

    assert storage_dir
           |> File.ls!()
           |> Enum.any?(&String.starts_with?(&1, "party"))
  end

  test "rejects an unsupported file type without retrying, and still cleans up S3",
       %{collection: collection, user: user} do
    key = "event_photo_uploads/#{collection.id}/#{Ecto.UUID.generate()}.xyz"
    put_s3_object(key, "not a real media file")

    job =
      make_job(%{
        "collection_id" => collection.id,
        "s3_key" => key,
        "filename" => "weird.xyz",
        "user_id" => user.id
      })

    assert :ok = EventPhotoUploadWorker.perform(job)
    refute s3_object_exists?(key)
  end

  test "returns an error and keeps the S3 object when the object doesn't exist yet",
       %{collection: collection, user: user} do
    key = "event_photo_uploads/#{collection.id}/never-uploaded.png"

    job =
      make_job(
        %{
          "collection_id" => collection.id,
          "s3_key" => key,
          "filename" => "never-uploaded.png",
          "user_id" => user.id
        },
        attempt: 1,
        max_attempts: 5
      )

    assert {:error, _reason} = EventPhotoUploadWorker.perform(job)
  end

  test "still returns an error on the final attempt (Oban will discard, not retry)",
       %{collection: collection, user: user} do
    key = "event_photo_uploads/#{collection.id}/never-uploaded-2.png"

    job =
      make_job(
        %{
          "collection_id" => collection.id,
          "s3_key" => key,
          "filename" => "never-uploaded-2.png",
          "user_id" => user.id
        },
        attempt: 5,
        max_attempts: 5
      )

    assert {:error, _reason} = EventPhotoUploadWorker.perform(job)
  end

  test "a download failure is never a reason to delete the S3 object, even on the final attempt",
       %{collection: collection, user: user} do
    key = "event_photo_uploads/#{collection.id}/#{Ecto.UUID.generate()}.png"
    put_s3_object(key, @tiny_png)

    job =
      make_job(
        %{
          "collection_id" => collection.id,
          "s3_key" => key,
          "filename" => "party.png",
          "user_id" => user.id
        },
        attempt: 5,
        max_attempts: 5
      )

    # Break just the download (S3Config.object_url/2's host resolution),
    # not the object's actual existence in S3 — final attempt, so this is
    # exactly the scenario that used to delete the source file unconditionally.
    original_base_url = Application.get_env(:ysc, :s3_base_url)
    Application.put_env(:ysc, :s3_base_url, "http://127.0.0.1:1")

    on_exit(fn ->
      if original_base_url do
        Application.put_env(:ysc, :s3_base_url, original_base_url)
      else
        Application.delete_env(:ysc, :s3_base_url)
      end
    end)

    result = EventPhotoUploadWorker.perform(job)

    if original_base_url do
      Application.put_env(:ysc, :s3_base_url, original_base_url)
    else
      Application.delete_env(:ysc, :s3_base_url)
    end

    assert {:error, _reason} = result
    assert s3_object_exists?(key)
  end
end
