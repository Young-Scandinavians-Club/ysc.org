defmodule YscWeb.Workers.ImageProcessorTest do
  @moduledoc """
  Tests for ImageProcessor worker module.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Media
  alias YscWeb.Workers.ImageProcessor
  import Ysc.TestDataFactory

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

  defp start_http_server(plug_module) do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)

    ref = :"image_processor_http_#{port}_#{System.unique_integer([:positive])}"

    {:ok, _} = Plug.Cowboy.http(plug_module, [], port: port, ref: ref)

    on_exit(fn -> Plug.Cowboy.shutdown(ref) end)

    port
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

    test "sets image processing_state to failed when downloaded bytes fail image validation" do
      _ = Application.ensure_all_started(:inets)
      port = start_http_server(ServeTextPlug)

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

    test "sets image processing_state to failed when HTTP response is not saved to file" do
      _ = Application.ensure_all_started(:inets)
      port = start_http_server(Serve404Plug)

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
