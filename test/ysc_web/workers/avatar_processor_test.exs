defmodule Ysc.Test.AvatarProcessor.MockS3Plug do
  @moduledoc false
  import Plug.Conn

  # 1x1 pixel PNG (same as MockImagePlug) for ExAws S3 get_object mocks
  @tiny_png Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            )

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    dispatch(conn)
  end

  # ExAws get_object: GET /{bucket}/{key} (path-style). Req 0.7+ may use POST.
  defp dispatch(%{method: method} = conn) when method in ["GET", "POST"] do
    path = conn.request_path |> String.trim_leading("/")

    cond do
      # Force a non-200 S3 read for failure tests (key must still match user prefix in DB)
      String.contains?(path, "/fail-trigger/original") ->
        conn
        |> put_resp_content_type("application/xml")
        |> send_resp(404, "")

      String.starts_with?(path, "avatars/") ->
        conn
        |> put_resp_content_type("image/png")
        |> send_resp(200, @tiny_png)

      true ->
        send_resp(conn, 404, "not found")
    end
  end

  defp dispatch(conn), do: send_resp(conn, 404, "not found")
end

defmodule YscWeb.Workers.AvatarProcessorTest do
  @moduledoc """
  Tests for AvatarProcessor Oban worker.

  Spins up a lightweight Cowboy HTTP server that mocks S3 `GET` for the raw
  object download. Uploads use `Ysc.Avatars.TestS3Uploader` in test (see
  `:avatars_s3_uploader` in config/test.exs) because ExAws multipart PUT against
  Cowboy mocks is unreliable after Mint/Cowboy upgrades.

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

  # Creates a user + avatar with `original_path` shaped like our real S3 public URL
  # (path includes `avatars/` prefix for MinIO path-style). ExAws uses `:ex_aws` host/port.
  defp create_avatar_for_user(s3_port, source \\ :upload) do
    user = user_fixture()
    suffix = Ecto.ULID.generate()
    key = "#{user.id}/#{suffix}/original.png"
    public_url = "http://127.0.0.1:#{s3_port}/avatars/#{key}"

    {:ok, avatar} =
      Avatars.create_avatar(user, %{
        source: source,
        original_path: public_url
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

  describe "resolve_original_s3_key/1" do
    test "rejects URLs whose object key is not under the avatar owner's user id" do
      user = user_fixture()

      assert {:error, :invalid_avatar_original_path} =
               AvatarProcessor.resolve_original_s3_key(%{
                 user_id: user.id,
                 original_path:
                   "https://cdn.example.org/other-user-id/x/original.webp"
               })
    end
  end

  # -------------------------------------------------------------------------
  # perform/1 - download failures
  # -------------------------------------------------------------------------

  describe "perform/1 when the image download fails" do
    test "returns error and marks the avatar as failed when S3 is unreachable" do
      user = user_fixture()
      suffix = Ecto.ULID.generate()
      key = "#{user.id}/#{suffix}/original.png"

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "http://127.0.0.1:99999/avatars/#{key}"
        })

      original = Application.get_env(:ex_aws, :s3)

      Application.put_env(:ex_aws, :s3,
        scheme: "http://",
        host: "127.0.0.1",
        port: 1
      )

      on_exit(fn ->
        if original do
          Application.put_env(:ex_aws, :s3, original)
        else
          Application.delete_env(:ex_aws, :s3)
        end
      end)

      assert {:error, _} = AvatarProcessor.perform(make_oban_job(avatar.id))

      assert Repo.get!(Avatars.Avatar, avatar.id).processing_state == :failed
    end

    test "returns error and marks the avatar as failed when S3 returns non-200 for get_object" do
      s3_port = start_http_server(Ysc.Test.AvatarProcessor.MockS3Plug)
      override_exaws_s3_port(s3_port)

      user = user_fixture()
      suffix = Ecto.ULID.generate()
      key = "#{user.id}/#{suffix}/fail-trigger/original.png"

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "http://127.0.0.1:#{s3_port}/avatars/#{key}"
        })

      assert {:error, _} = AvatarProcessor.perform(make_oban_job(avatar.id))

      assert Repo.get!(Avatars.Avatar, avatar.id).processing_state == :failed
    end
  end

  # -------------------------------------------------------------------------
  # perform/1 - happy path
  # -------------------------------------------------------------------------

  describe "perform/1 happy path (S3 mock)" do
    setup do
      s3_port = start_http_server(Ysc.Test.AvatarProcessor.MockS3Plug)
      override_exaws_s3_port(s3_port)
      {:ok, s3_port: s3_port}
    end

    test "returns :ok and marks the avatar as completed", %{s3_port: s3_port} do
      {_user, avatar} = create_avatar_for_user(s3_port)

      assert :ok = AvatarProcessor.perform(make_oban_job(avatar.id))

      updated = Repo.get!(Avatars.Avatar, avatar.id)
      assert updated.processing_state == :completed
      assert is_binary(updated.thumb_path) and updated.thumb_path != ""
      assert is_binary(updated.profile_path) and updated.profile_path != ""
      assert is_binary(updated.large_path) and updated.large_path != ""
    end

    test "sets the user's current avatar when the user has none", %{
      s3_port: s3_port
    } do
      {user, avatar} = create_avatar_for_user(s3_port, :upload)

      # Confirm no current avatar before processing
      assert is_nil(Repo.reload!(user).current_avatar_id)

      assert :ok = AvatarProcessor.perform(make_oban_job(avatar.id))

      assert Repo.reload!(user).current_avatar_id == avatar.id
    end

    test "upload source always replaces the current avatar", %{s3_port: s3_port} do
      {user, new_avatar} = create_avatar_for_user(s3_port, :upload)
      existing = set_existing_current_avatar(user)

      assert Repo.reload!(user).current_avatar_id == existing.id

      assert :ok = AvatarProcessor.perform(make_oban_job(new_avatar.id))

      # Upload source always wins, even when a current avatar exists
      assert Repo.reload!(user).current_avatar_id == new_avatar.id
    end

    test "OAuth source does not replace an existing current avatar", %{
      s3_port: s3_port
    } do
      {user, oauth_avatar} = create_avatar_for_user(s3_port, :google)
      existing = set_existing_current_avatar(user)

      assert Repo.reload!(user).current_avatar_id == existing.id

      assert :ok = AvatarProcessor.perform(make_oban_job(oauth_avatar.id))

      # OAuth source must not override when a current avatar already exists
      assert Repo.reload!(user).current_avatar_id == existing.id
    end

    test "OAuth source sets the current avatar when the user has none", %{
      s3_port: s3_port
    } do
      {user, oauth_avatar} = create_avatar_for_user(s3_port, :google)

      assert is_nil(Repo.reload!(user).current_avatar_id)

      assert :ok = AvatarProcessor.perform(make_oban_job(oauth_avatar.id))

      assert Repo.reload!(user).current_avatar_id == oauth_avatar.id
    end

    test "cleans up all temp files after successful processing", %{
      s3_port: s3_port
    } do
      {_user, avatar} = create_avatar_for_user(s3_port)

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
      s3_port: s3_port
    } do
      {_user, avatar} = create_avatar_for_user(s3_port)

      suffix = Ecto.ULID.generate()
      user_id = avatar.user_id
      bad_key = "#{user_id}/#{suffix}/original.png"

      failing_avatar =
        avatar
        |> Ecto.Changeset.change(
          original_path: "http://127.0.0.1:99999/avatars/#{bad_key}"
        )
        |> Repo.update!()

      original = Application.get_env(:ex_aws, :s3)

      Application.put_env(:ex_aws, :s3,
        scheme: "http://",
        host: "127.0.0.1",
        port: 1
      )

      on_exit(fn ->
        if original do
          Application.put_env(:ex_aws, :s3, original)
        else
          Application.delete_env(:ex_aws, :s3)
        end
      end)

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
