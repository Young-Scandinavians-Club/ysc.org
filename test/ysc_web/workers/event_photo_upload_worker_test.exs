defmodule Ysc.Test.EventPhotoUploadWorker.MockS3Plug do
  @moduledoc """
  Stands in for S3 GET/DELETE. `ExAws.S3.download_file/3`'s chunked download
  strategy issues GET (sometimes POST, depending on Req/ExAws version) against
  real MinIO in a way MinIO rejects locally — see
  `YscWeb.Workers.ImageProcessorTest` for the same work-around.
  """
  import Plug.Conn

  @tiny_png Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            )

  def init(opts), do: opts

  def call(%{method: "DELETE"} = conn, _opts), do: send_resp(conn, 204, "")

  def call(%{method: "HEAD"} = conn, _opts) do
    path = String.trim_leading(conn.request_path, "/")

    if String.contains?(path, "missing") do
      send_resp(conn, 404, "")
    else
      conn
      |> put_resp_content_type("image/png")
      |> put_resp_header(
        "content-length",
        Integer.to_string(byte_size(@tiny_png))
      )
      |> send_resp(200, "")
    end
  end

  def call(%{method: method} = conn, _opts) when method in ["GET", "POST"] do
    path = String.trim_leading(conn.request_path, "/")

    if String.contains?(path, "missing") do
      conn |> put_resp_content_type("application/xml") |> send_resp(404, "")
    else
      conn |> put_resp_content_type("image/png") |> send_resp(200, @tiny_png)
    end
  end

  def call(conn, _opts), do: send_resp(conn, 404, "not found")
end

defmodule YscWeb.Workers.EventPhotoUploadWorkerTest do
  @moduledoc """
  `async: false` because the S3 mock overrides the global `:ex_aws, :s3` config
  (same constraint as `YscWeb.Workers.AvatarProcessorTest`).
  """
  use Ysc.DataCase, async: false

  alias Ysc.EventPhotos
  alias YscWeb.Workers.EventPhotoUploadWorker

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  setup do
    prev = Application.get_env(:ysc, :google_photos, [])

    Application.put_env(
      :ysc,
      :google_photos,
      Keyword.put(prev, :dev_stub, true)
    )

    original_s3 = Application.get_env(:ex_aws, :s3)

    port =
      Ysc.HttpTestServer.ensure_started(
        Ysc.Test.EventPhotoUploadWorker.MockS3Plug,
        :event_photo_upload_s3
      )

    Application.put_env(:ex_aws, :s3,
      scheme: "http://",
      host: "127.0.0.1",
      port: port
    )

    on_exit(fn ->
      Application.put_env(:ysc, :google_photos, prev)

      if original_s3 do
        Application.put_env(:ex_aws, :s3, original_s3)
      else
        Application.delete_env(:ex_aws, :s3)
      end
    end)

    organizer = user_fixture()
    user = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id, state: :published})
    {:ok, collection} = EventPhotos.ensure_collection_for_event(event)

    %{event: event, collection: collection, user: user}
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

  test "downloads from S3 and hands the file off to Google Photos", %{
    collection: collection,
    user: user
  } do
    job =
      make_job(%{
        "collection_id" => collection.id,
        "s3_key" => "event_photo_uploads/#{collection.id}/found.png",
        "filename" => "party.png",
        "user_id" => user.id
      })

    assert :ok = EventPhotoUploadWorker.perform(job)

    storage_dir =
      Path.join(Ysc.SafeFile.dev_event_photos_root(), collection.event_id)

    assert storage_dir
           |> File.ls!()
           |> Enum.any?(&String.starts_with?(&1, "party"))
  end

  test "rejects an unsupported file type without retrying", %{
    collection: collection,
    user: user
  } do
    job =
      make_job(%{
        "collection_id" => collection.id,
        "s3_key" => "event_photo_uploads/#{collection.id}/found.xyz",
        "filename" => "weird.xyz",
        "user_id" => user.id
      })

    assert :ok = EventPhotoUploadWorker.perform(job)
  end

  test "returns an error (for Oban to retry) when the S3 object is missing", %{
    collection: collection,
    user: user
  } do
    job =
      make_job(
        %{
          "collection_id" => collection.id,
          "s3_key" => "event_photo_uploads/#{collection.id}/missing.png",
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
    job =
      make_job(
        %{
          "collection_id" => collection.id,
          "s3_key" => "event_photo_uploads/#{collection.id}/missing.png",
          "filename" => "never-uploaded.png",
          "user_id" => user.id
        },
        attempt: 5,
        max_attempts: 5
      )

    assert {:error, _reason} = EventPhotoUploadWorker.perform(job)
  end
end
