defmodule YscWeb.Admin.EditingPresenceTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.UserDisplay
  alias YscWeb.Admin.EditingPresence
  alias YscWeb.Presence

  # Untracks at the end of the test so a lingering entry can't leak into
  # another test sharing the same topic (they run in different processes,
  # but belt-and-suspenders since Presence state isn't sandboxed like the DB).
  defp track_fixture(type, resource_id, user, key \\ nil) do
    key = key || "socket-#{System.unique_integer([:positive])}"
    socket = %{id: key}
    {:ok, _ref} = EditingPresence.track(socket, type, resource_id, user)

    on_exit(fn ->
      Presence.untrack(self(), EditingPresence.topic(type), key)
    end)

    key
  end

  describe "topic/1" do
    test "maps each resource type to its own topic" do
      assert EditingPresence.topic(:post) == "presence:posts"
      assert EditingPresence.topic(:newsletter) == "presence:newsletters"
      assert EditingPresence.topic(:event) == "presence:events"
    end
  end

  describe "track/4 and editors/3" do
    test "returns editors currently tracked on a resource, excluding the caller" do
      resource_id = Ecto.ULID.generate()
      editor = user_fixture(%{first_name: "Jane", last_name: "Doe"})
      viewer = user_fixture()

      track_fixture(:post, resource_id, editor)

      [entry] = EditingPresence.editors(:post, resource_id, viewer.id)
      assert entry.user_id == editor.id
      assert entry.name == UserDisplay.full_name(editor)
      assert is_binary(entry.avatar_url)
    end

    test "excludes the current user's own presence" do
      resource_id = Ecto.ULID.generate()
      user = user_fixture()

      track_fixture(:post, resource_id, user)

      assert EditingPresence.editors(:post, resource_id, user.id) == []
    end

    test "returns an empty list when nobody is editing the resource" do
      resource_id = Ecto.ULID.generate()
      viewer = user_fixture()

      assert EditingPresence.editors(:post, resource_id, viewer.id) == []
    end

    test "does not include editors of a different resource" do
      resource_id = Ecto.ULID.generate()
      other_resource_id = Ecto.ULID.generate()
      editor = user_fixture()
      viewer = user_fixture()

      track_fixture(:post, other_resource_id, editor)

      assert EditingPresence.editors(:post, resource_id, viewer.id) == []
    end

    test "does not leak across resource types sharing the same resource_id" do
      resource_id = Ecto.ULID.generate()
      editor = user_fixture()
      viewer = user_fixture()

      track_fixture(:post, resource_id, editor)

      assert EditingPresence.editors(:newsletter, resource_id, viewer.id) == []
      assert EditingPresence.editors(:event, resource_id, viewer.id) == []
    end

    test "dedupes the same user tracked under multiple keys (e.g. two tabs)" do
      resource_id = Ecto.ULID.generate()
      editor = user_fixture()
      viewer = user_fixture()

      track_fixture(:post, resource_id, editor)
      track_fixture(:post, resource_id, editor)

      assert [entry] = EditingPresence.editors(:post, resource_id, viewer.id)
      assert entry.user_id == editor.id
    end

    test "lists multiple distinct editors on the same resource" do
      resource_id = Ecto.ULID.generate()
      editor_a = user_fixture()
      editor_b = user_fixture()
      viewer = user_fixture()

      track_fixture(:post, resource_id, editor_a)
      track_fixture(:post, resource_id, editor_b)

      ids =
        :post
        |> EditingPresence.editors(resource_id, viewer.id)
        |> Enum.map(& &1.user_id)
        |> Enum.sort()

      assert ids == Enum.sort([editor_a.id, editor_b.id])
    end
  end

  describe "untrack/2" do
    test "removes the tracked entry so it no longer appears" do
      resource_id = Ecto.ULID.generate()
      editor = user_fixture()
      viewer = user_fixture()
      socket = %{id: "untrack-socket-#{System.unique_integer([:positive])}"}

      {:ok, _ref} = EditingPresence.track(socket, :post, resource_id, editor)
      assert [_] = EditingPresence.editors(:post, resource_id, viewer.id)

      :ok = EditingPresence.untrack(socket, :post)
      assert EditingPresence.editors(:post, resource_id, viewer.id) == []
    end

    test "allows tracking a different resource_id under the same key afterwards" do
      first_id = Ecto.ULID.generate()
      second_id = Ecto.ULID.generate()
      editor = user_fixture()
      viewer = user_fixture()
      socket = %{id: "switch-socket-#{System.unique_integer([:positive])}"}

      {:ok, _ref} = EditingPresence.track(socket, :event, first_id, editor)
      :ok = EditingPresence.untrack(socket, :event)
      {:ok, _ref} = EditingPresence.track(socket, :event, second_id, editor)

      on_exit(fn ->
        Presence.untrack(self(), EditingPresence.topic(:event), socket.id)
      end)

      assert EditingPresence.editors(:event, first_id, viewer.id) == []
      assert [entry] = EditingPresence.editors(:event, second_id, viewer.id)
      assert entry.user_id == editor.id
    end
  end

  describe "editors_by_resource/2" do
    test "groups editors by resource_id, excluding the current user" do
      resource_a = Ecto.ULID.generate()
      resource_b = Ecto.ULID.generate()
      editor_a = user_fixture()
      editor_b = user_fixture()
      viewer = user_fixture()

      track_fixture(:post, resource_a, editor_a)
      track_fixture(:post, resource_b, editor_b)

      result = EditingPresence.editors_by_resource(:post, viewer.id)

      assert [%{user_id: id_a}] = Map.fetch!(result, resource_a)
      assert id_a == editor_a.id
      assert [%{user_id: id_b}] = Map.fetch!(result, resource_b)
      assert id_b == editor_b.id
    end

    test "omits a resource entirely once its only editor is the caller" do
      resource_id = Ecto.ULID.generate()
      user = user_fixture()

      track_fixture(:post, resource_id, user)

      result = EditingPresence.editors_by_resource(:post, user.id)
      refute Map.has_key?(result, resource_id)
    end

    test "returns an empty map when nothing is tracked" do
      viewer = user_fixture()

      # A fresh, unused resource type/id combination has nothing tracked, but
      # since the map is global we only assert our own resource is absent.
      resource_id = Ecto.ULID.generate()
      result = EditingPresence.editors_by_resource(:newsletter, viewer.id)
      refute Map.has_key?(result, resource_id)
    end
  end

  describe "subscribe/1" do
    test "subscribes the caller to the resource type's topic" do
      assert :ok = EditingPresence.subscribe(:post)

      resource_id = Ecto.ULID.generate()
      editor = user_fixture()

      track_fixture(:post, resource_id, editor)

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "presence:posts",
        event: "presence_diff"
      }
    end
  end
end
