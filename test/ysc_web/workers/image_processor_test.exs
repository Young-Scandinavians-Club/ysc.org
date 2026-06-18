defmodule Ysc.Test.ImageProcessor.MockS3Plug do
  @moduledoc false
  import Plug.Conn

  @tiny_png_path Path.expand("../../support/fixtures/tiny.png", __DIR__)

  def init(opts), do: opts

  def call(conn, _opts) do
    content = File.read!(@tiny_png_path)

    conn
    |> put_resp_content_type("image/png")
    |> send_resp(200, content)
  end
end

defmodule YscWeb.Workers.ImageProcessorTest do
  @moduledoc """
  Tests for ImageProcessor worker module.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Media
  alias YscWeb.Workers.ImageProcessor
  import Ysc.TestDataFactory

  @tiny_png_path Path.expand("../../support/fixtures/tiny.png", __DIR__)

  defmodule ServePngPlug do
    @moduledoc false
    import Plug.Conn

    @png_path Path.expand("../../support/fixtures/tiny.png", __DIR__)

    def init(opts), do: opts

    def call(conn, _opts) do
      content = File.read!(@png_path)

      conn
      |> put_resp_content_type("image/png")
      |> send_resp(200, content)
    end
  end

  defmodule ServeTextPlug do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "not a valid image")
    end
  end

  defmodule Serve404Plug do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "missing")
    end
  end

  setup_all do
    {:ok,
     http_ports: %{
       png:
         Ysc.HttpTestServer.ensure_started(ServePngPlug, :image_processor_png),
       text:
         Ysc.HttpTestServer.ensure_started(ServeTextPlug, :image_processor_text),
       not_found:
         Ysc.HttpTestServer.ensure_started(Serve404Plug, :image_processor_404)
     }}
  end

  defp start_s3_mock_server do
    Ysc.HttpTestServer.ensure_started(
      Ysc.Test.ImageProcessor.MockS3Plug,
      :image_processor_s3
    )
  end

  defp override_exaws_s3_port(port) do
    original = Application.get_env(:ex_aws, :s3)

    Application.put_env(:ex_aws, :s3,
      scheme: "http://",
      host: "127.0.0.1",
      port: port
    )

    on_exit(fn ->
      if original do
        Application.put_env(:ex_aws, :s3, original)
      else
        Application.delete_env(:ex_aws, :s3)
      end
    end)
  end

  defp override_s3_base_url(url) do
    original = Application.get_env(:ysc, :s3_base_url)

    Application.put_env(:ysc, :s3_base_url, url)

    on_exit(fn ->
      if original do
        Application.put_env(:ysc, :s3_base_url, original)
      else
        Application.delete_env(:ysc, :s3_base_url)
      end
    end)
  end

  defp make_job(image_id) do
    %Oban.Job{
      id: 1,
      args: %{"id" => image_id},
      worker: "YscWeb.Workers.ImageProcessor",
      queue: "media",
      state: "available",
      attempt: 1
    }
  end

  describe "perform/1 with object storage URLs" do
    test "downloads raw bytes from path-style object storage URL when upload_data key is absent" do
      port = start_s3_mock_server()
      override_exaws_s3_port(port)
      override_s3_base_url("http://127.0.0.1:#{port}")

      bucket = Ysc.S3Config.bucket_name()
      object_key = "wp-import/tiny.png"
      raw_url = "http://127.0.0.1:#{port}/#{bucket}/#{object_key}"

      image =
        create_test_image(%{
          raw_image_path: raw_url,
          upload_data: nil,
          optimized_image_path: nil,
          thumbnail_path: nil,
          processing_state: "unprocessed"
        })

      assert {:ok, result} = ImageProcessor.perform(make_job(image.id))
      assert result.processing_state == :completed

      reloaded = Media.fetch_image(image.id)
      assert reloaded.processing_state == :completed
      assert is_binary(reloaded.optimized_image_path)
    end

    test "downloads raw bytes from Tigris virtual-host URL when upload_data key is absent" do
      port = start_s3_mock_server()
      override_exaws_s3_port(port)

      bucket = Ysc.S3Config.bucket_name()
      object_key = "wp-import/tiny.png"
      raw_url = "https://#{bucket}.fly.storage.tigris.dev/#{object_key}"

      image =
        create_test_image(%{
          raw_image_path: raw_url,
          upload_data: nil,
          optimized_image_path: nil,
          thumbnail_path: nil,
          processing_state: "unprocessed"
        })

      assert {:ok, result} = ImageProcessor.perform(make_job(image.id))
      assert result.processing_state == :completed
    end

    test "prefers explicit upload_data key over raw_image_path URL derivation" do
      port = start_s3_mock_server()
      override_exaws_s3_port(port)
      override_s3_base_url("http://127.0.0.1:#{port}")

      bucket = Ysc.S3Config.bucket_name()
      object_key = "wp-import/tiny.png"
      raw_url = "http://127.0.0.1:#{port}/#{bucket}/wrong-key.png"

      image =
        create_test_image(%{
          raw_image_path: raw_url,
          upload_data: %{"key" => object_key},
          optimized_image_path: nil,
          thumbnail_path: nil,
          processing_state: "unprocessed"
        })

      assert {:ok, result} = ImageProcessor.perform(make_job(image.id))
      assert result.processing_state == :completed
    end
  end

  describe "perform/1" do
    test "returns error when image is not found" do
      missing_id = Ecto.ULID.generate()

      job = %Oban.Job{
        id: 1,
        args: %{"id" => missing_id},
        worker: "YscWeb.Workers.ImageProcessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      result = ImageProcessor.perform(job)
      assert {:error, "Image not found"} = result
    end

    test "sets image processing_state to failed when downloaded bytes fail image validation",
         %{http_ports: %{text: port}} do
      _ = Application.ensure_all_started(:inets)

      image =
        create_test_image(%{
          raw_image_path: "http://127.0.0.1:#{port}/fake.jpg",
          processing_state: "unprocessed"
        })

      job = %Oban.Job{
        id: 1,
        args: %{"id" => image.id},
        worker: "YscWeb.Workers.ImageProcessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      assert match?({:error, _}, ImageProcessor.perform(job))

      updated = Media.fetch_image(image.id)
      assert updated.processing_state == :failed
    end

    test "sets image processing_state to failed when HTTP response is not saved to file",
         %{http_ports: %{not_found: port}} do
      _ = Application.ensure_all_started(:inets)

      image =
        create_test_image(%{
          raw_image_path: "http://127.0.0.1:#{port}/missing.jpg",
          processing_state: "unprocessed"
        })

      job = %Oban.Job{
        id: 1,
        args: %{"id" => image.id},
        worker: "YscWeb.Workers.ImageProcessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      assert match?({:error, _}, ImageProcessor.perform(job))

      updated = Media.fetch_image(image.id)
      assert updated.processing_state == :failed
    end

    test "sets image processing_state to failed when download fails" do
      raw_url = "http://127.0.0.1:1/image.jpg"

      image =
        create_test_image(%{
          raw_image_path: raw_url,
          processing_state: "unprocessed"
        })

      job = %Oban.Job{
        id: 1,
        args: %{"id" => image.id},
        worker: "YscWeb.Workers.ImageProcessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      result = ImageProcessor.perform(job)
      assert match?({:error, _}, result)

      updated = Media.fetch_image(image.id)
      assert updated.processing_state == :failed
    end

    test "reuses an existing completed image when the raw file hash matches",
         %{http_ports: %{png: port}} do
      _ = Application.ensure_all_started(:inets)

      expected_hash = Media.compute_file_hash(@tiny_png_path)

      source =
        create_test_image(%{
          optimized_image_path: "https://cdn.example.com/dedup_opt.webp",
          thumbnail_path: "https://cdn.example.com/dedup_thumb.webp",
          blur_hash: "L6Pj0^jE.AyXtest",
          width: 1,
          height: 1,
          processing_state: "completed",
          content_hash: expected_hash
        })

      target =
        create_test_image(%{
          raw_image_path: "http://127.0.0.1:#{port}/tiny.png",
          processing_state: "unprocessed"
        })

      # Pre-write the PNG to the temp path the worker will use.
      # This ensures validate_image and compute_file_hash operate on real PNG
      # bytes regardless of how Req handles the `into:` option at runtime.
      tmp_dir = "/tmp/image_processor"
      File.mkdir_p!(tmp_dir)
      tmp_file = Path.join(tmp_dir, target.id)
      File.copy!(@tiny_png_path, tmp_file)
      on_exit(fn -> File.rm(tmp_file) end)

      job = %Oban.Job{
        id: 1,
        args: %{"id" => target.id},
        worker: "YscWeb.Workers.ImageProcessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      assert {:ok, result} = ImageProcessor.perform(job)
      assert result.processing_state == :completed
      assert result.optimized_image_path == source.optimized_image_path
      assert result.thumbnail_path == source.thumbnail_path

      reloaded = Media.fetch_image(target.id)
      assert reloaded.processing_state == :completed
      assert reloaded.optimized_image_path == source.optimized_image_path
      assert reloaded.thumbnail_path == source.thumbnail_path
    end

    test "does not short-circuit when the only matching hash belongs to the image itself",
         %{http_ports: %{png: port}} do
      _ = Application.ensure_all_started(:inets)

      expected_hash = Media.compute_file_hash(@tiny_png_path)

      # Pre-seed the image's own hash so `find_image_by_content_hash` returns it.
      # The `existing.id != image.id` guard must prevent self-reuse and let
      # normal processing run.
      self_image =
        create_test_image(%{
          raw_image_path: "http://127.0.0.1:#{port}/tiny.png",
          processing_state: "unprocessed",
          content_hash: expected_hash
        })

      tmp_dir = "/tmp/image_processor"
      File.mkdir_p!(tmp_dir)
      tmp_file = Path.join(tmp_dir, self_image.id)
      File.copy!(@tiny_png_path, tmp_file)
      on_exit(fn -> File.rm(tmp_file) end)

      job = %Oban.Job{
        id: 1,
        args: %{"id" => self_image.id},
        worker: "YscWeb.Workers.ImageProcessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      # The guard prevents self-reuse; normal processing runs instead.
      # If the dedup path had been taken (incorrectly), `reuse_existing_processed_image`
      # would mark the image :completed with the fixture's default optimized path.
      # We verify the guard works regardless of whether S3 is available.
      result = ImageProcessor.perform(job)
      reloaded = Media.fetch_image(self_image.id)

      case result do
        {:ok, _} ->
          # S3 available: full processing completed with a real S3 path.
          assert reloaded.processing_state == :completed

          refute reloaded.optimized_image_path ==
                   "/uploads/test_image_optimized.jpg"

        {:error, _} ->
          # S3 unavailable: normal processing attempted but failed — the image
          # is :failed, not :completed via the dedup reuse path.
          assert reloaded.processing_state == :failed
      end
    end
  end

  describe "new/1" do
    test "builds a job with the given image id" do
      image = create_test_image()
      changeset = ImageProcessor.new(%{id: image.id})

      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :worker) ==
               "YscWeb.Workers.ImageProcessor"

      assert Ecto.Changeset.get_change(changeset, :queue) == "media"

      args = Ecto.Changeset.get_change(changeset, :args) || %{}
      assert args["id"] == image.id or args[:id] == image.id
    end
  end
end
