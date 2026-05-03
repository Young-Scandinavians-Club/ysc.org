defmodule Ysc.Test.AvatarProcessor.Serve404Plug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "not found")
  end
end

defmodule Ysc.Test.AvatarProcessor.MockImagePlug do
  @moduledoc false
  import Plug.Conn

  # 1x1 pixel PNG, inline to avoid file-path resolution at compile time
  @tiny_png Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            )

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("image/png")
    |> send_resp(200, @tiny_png)
  end
end

defmodule Ysc.Test.AvatarProcessor.MockS3Plug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    dispatch(conn)
  end

  # Initiate multipart upload: POST /{bucket}/{key}?uploads
  defp dispatch(%{method: "POST", query_params: %{"uploads" => _}} = conn) do
    {:ok, _body, conn} = read_body(conn)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, """
    <?xml version="1.0" encoding="UTF-8"?>
    <InitiateMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <Bucket>avatars</Bucket>
      <Key>key</Key>
      <UploadId>mock-upload-id-12345</UploadId>
    </InitiateMultipartUploadResult>
    """)
  end

  # Upload part: PUT /{bucket}/{key}?partNumber=N&uploadId=xxx
  defp dispatch(%{method: "PUT", query_params: %{"partNumber" => _}} = conn) do
    {:ok, _body, conn} = read_body(conn)

    conn
    |> put_resp_header("etag", ~s("mock-etag-abc123"))
    |> send_resp(200, "")
  end

  # Complete multipart upload: POST /{bucket}/{key}?uploadId=xxx
  defp dispatch(%{method: "POST", query_params: %{"uploadId" => _}} = conn) do
    {:ok, _body, conn} = read_body(conn)
    path = conn.request_path |> String.trim_leading("/")

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, """
    <?xml version="1.0" encoding="UTF-8"?>
    <CompleteMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <Location>http://localhost/#{path}</Location>
      <Bucket>avatars</Bucket>
      <Key>key</Key>
      <ETag>"mock-etag-final"</ETag>
    </CompleteMultipartUploadResult>
    """)
  end

  defp dispatch(conn), do: send_resp(conn, 200, "")
end

defmodule YscWeb.Workers.AvatarProcessorTest do
  @moduledoc """
  Tests for AvatarProcessor Oban worker.

  The happy-path tests spin up two lightweight Cowboy HTTP servers:
    - An image server that serves a 1×1 PNG (mocks the original avatar download).
    - An S3-compatible server that speaks the multipart-upload protocol
      (mocks ExAws S3 uploads without needing a real MinIO instance).

  Because the S3 mock requires overriding the global `Application.put_env(:ex_aws, :s3, …)`
  config, this module runs with `async: false`.
  """

  use Ysc.DataCase, async: false

  alias Ysc.Avatars
  alias Ysc.Repo
  alias YscWeb.Workers.AvatarProcessor

  import Ysc.AccountsFixtures

  # -------------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------------

  defp make_oban_job(avatar_id) do
    %Oban.Job{
      id: 1,
      args: %{"id" => avatar_id},
      worker: "YscWeb.Workers.AvatarProcessor",
      queue: "media",
      state: "available",
      attempt: 1
    }
  end

  # Starts a Plug.Cowboy HTTP server on a random free port and registers
  # an on_exit callback that shuts it down at the end of the test.
  # Returns the allocated port number.
  defp start_http_server(plug_module) do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)

    ref = :"avatar_proc_http_#{port}_#{System.unique_integer([:positive])}"
    {:ok, _} = Plug.Cowboy.http(plug_module, [], port: port, ref: ref)

    on_exit(fn -> Plug.Cowboy.shutdown(ref) end)

    port
  end

  # Temporarily redirects ExAws S3 calls to `port` on localhost and restores
  # the original config via on_exit.
  defp override_exaws_s3_port(port) do
    original = Application.get_env(:ex_aws, :s3)

    Application.put_env(:ex_aws, :s3,
      scheme: "http://",
      host: "localhost",
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

  # Creates a user + an avatar whose original_path points to a locally running
  # image server.  Returns {user, avatar}.
  defp create_avatar_for_user(image_port, source \\ :upload) do
    user = user_fixture()

    {:ok, avatar} =
      Avatars.create_avatar(user, %{
        source: source,
        original_path: "http://127.0.0.1:#{image_port}/avatar.png"
      })

    {user, avatar}
  end

  # Creates a "completed" avatar for a user and sets it as the user's current avatar.
  defp set_existing_current_avatar(user) do
    {:ok, placeholder} =
      Avatars.create_avatar(user, %{
        source: :upload,
        original_path: "https://example.com/placeholder.webp"
      })

    {:ok, placeholder} =
      Avatars.update_processed_avatar(placeholder, %{
        processing_state: :completed,
        thumb_path: "https://example.com/t.webp",
        profile_path: "https://example.com/p.webp",
        large_path: "https://example.com/l.webp"
      })

    {:ok, _user} = Avatars.set_current_avatar(user, placeholder.id)

    placeholder
  end

  # -------------------------------------------------------------------------
  # perform/1 - avatar not found
  # -------------------------------------------------------------------------

  describe "perform/1 when avatar does not exist" do
    test "discards the job" do
      job = make_oban_job(Ecto.ULID.generate())

      assert {:discard, :avatar_not_found} = AvatarProcessor.perform(job)
    end
  end

  # -------------------------------------------------------------------------
  # perform/1 - download failures
  # -------------------------------------------------------------------------

  describe "perform/1 when the image download fails" do
    test "returns error and marks the avatar as failed when the server is unreachable" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          # Port 1 is not open (econnrefused). Req retries that by default; the worker
          # passes `retry: false` so failures stay fast and Oban handles retries.
          original_path: "http://127.0.0.1:1/avatar.png"
        })

      assert {:error, _} = AvatarProcessor.perform(make_oban_job(avatar.id))

      assert Repo.get!(Avatars.Avatar, avatar.id).processing_state == :failed
    end

    test "returns error and marks the avatar as failed when the server returns a non-200 status" do
      port = start_http_server(Ysc.Test.AvatarProcessor.Serve404Plug)

      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "http://127.0.0.1:#{port}/avatar.png"
        })

      assert {:error, _} = AvatarProcessor.perform(make_oban_job(avatar.id))

      assert Repo.get!(Avatars.Avatar, avatar.id).processing_state == :failed
    end
  end

  # -------------------------------------------------------------------------
  # perform/1 - happy path
  # -------------------------------------------------------------------------

  describe "perform/1 happy path (image server + S3 mock)" do
    setup do
      image_port = start_http_server(Ysc.Test.AvatarProcessor.MockImagePlug)
      s3_port = start_http_server(Ysc.Test.AvatarProcessor.MockS3Plug)
      override_exaws_s3_port(s3_port)
      {:ok, image_port: image_port}
    end

    test "returns :ok and marks the avatar as completed", %{
      image_port: image_port
    } do
      {_user, avatar} = create_avatar_for_user(image_port)

      assert :ok = AvatarProcessor.perform(make_oban_job(avatar.id))

      updated = Repo.get!(Avatars.Avatar, avatar.id)
      assert updated.processing_state == :completed
      assert is_binary(updated.thumb_path) and updated.thumb_path != ""
      assert is_binary(updated.profile_path) and updated.profile_path != ""
      assert is_binary(updated.large_path) and updated.large_path != ""
    end

    test "sets the user's current avatar when the user has none", %{
      image_port: image_port
    } do
      {user, avatar} = create_avatar_for_user(image_port, :upload)

      # Confirm no current avatar before processing
      assert is_nil(Repo.reload!(user).current_avatar_id)

      assert :ok = AvatarProcessor.perform(make_oban_job(avatar.id))

      assert Repo.reload!(user).current_avatar_id == avatar.id
    end

    test "upload source always replaces the current avatar", %{
      image_port: image_port
    } do
      {user, new_avatar} = create_avatar_for_user(image_port, :upload)
      existing = set_existing_current_avatar(user)

      assert Repo.reload!(user).current_avatar_id == existing.id

      assert :ok = AvatarProcessor.perform(make_oban_job(new_avatar.id))

      # Upload source always wins, even when a current avatar exists
      assert Repo.reload!(user).current_avatar_id == new_avatar.id
    end

    test "OAuth source does not replace an existing current avatar", %{
      image_port: image_port
    } do
      {user, oauth_avatar} = create_avatar_for_user(image_port, :google)
      existing = set_existing_current_avatar(user)

      assert Repo.reload!(user).current_avatar_id == existing.id

      assert :ok = AvatarProcessor.perform(make_oban_job(oauth_avatar.id))

      # OAuth source must not override when a current avatar already exists
      assert Repo.reload!(user).current_avatar_id == existing.id
    end

    test "OAuth source sets the current avatar when the user has none", %{
      image_port: image_port
    } do
      {user, oauth_avatar} = create_avatar_for_user(image_port, :google)

      assert is_nil(Repo.reload!(user).current_avatar_id)

      assert :ok = AvatarProcessor.perform(make_oban_job(oauth_avatar.id))

      assert Repo.reload!(user).current_avatar_id == oauth_avatar.id
    end

    test "cleans up all temp files after successful processing", %{
      image_port: image_port
    } do
      {_user, avatar} = create_avatar_for_user(image_port)

      assert :ok = AvatarProcessor.perform(make_oban_job(avatar.id))

      base = Path.join("/tmp/avatar_processor", avatar.id)

      for suffix <- [
            "_raw",
            "_stripped.webp",
            "_thumb.webp",
            "_profile.webp",
            "_large.webp"
          ] do
        refute File.exists?("#{base}#{suffix}"),
               "expected #{suffix} to be deleted after success"
      end
    end

    test "cleans up all temp files after a processing failure", %{
      image_port: image_port
    } do
      {_user, avatar} = create_avatar_for_user(image_port)

      # Simulate download failure after a valid avatar row exists (same as unreachable
      # URL / refused port once Req retries are disabled on the worker).
      failing_avatar =
        avatar
        |> Ecto.Changeset.change(original_path: "http://127.0.0.1:1/bad.png")
        |> Repo.update!()

      assert {:error, _} =
               AvatarProcessor.perform(make_oban_job(failing_avatar.id))

      base = Path.join("/tmp/avatar_processor", failing_avatar.id)

      for suffix <- [
            "_raw",
            "_stripped.webp",
            "_thumb.webp",
            "_profile.webp",
            "_large.webp"
          ] do
        refute File.exists?("#{base}#{suffix}"),
               "expected #{suffix} to be deleted after failure"
      end
    end
  end
end
