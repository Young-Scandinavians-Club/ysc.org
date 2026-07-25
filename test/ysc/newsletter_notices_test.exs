defmodule Ysc.NewsletterNoticesTest do
  use Ysc.DataCase, async: true

  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Newsletter
  alias Ysc.Newsletter.Notice

  defp admin_fixture, do: user_fixture(%{role: "admin"})

  describe "create_notice/2" do
    test "creates a notice with name and body" do
      user = admin_fixture()

      assert {:ok, %Notice{} = notice} =
               Newsletter.create_notice(
                 %{"name" => "Parking", "body" => "<p>Park in lot B</p>"},
                 created_by_id: user.id
               )

      assert notice.name == "Parking"
      assert notice.body =~ "Park in lot B"
      assert notice.creator_id == user.id
    end

    test "scrubs unsafe HTML from body" do
      assert {:ok, notice} =
               Newsletter.create_notice(%{
                 "name" => "Unsafe",
                 "body" => "<p>Hi</p><script>alert(1)</script>"
               })

      refute notice.body =~ "<script>"
      assert notice.body =~ "Hi"
    end

    test "requires name and body" do
      assert {:error, changeset} = Newsletter.create_notice(%{})

      assert %{name: ["can't be blank"], body: ["can't be blank"]} =
               errors_on(changeset)
    end
  end

  describe "list_notices/0" do
    test "returns notices newest first with creator preloaded" do
      user =
        user_fixture(%{role: "admin", first_name: "Ada", last_name: "Lovelace"})

      {:ok, older} =
        Newsletter.create_notice(
          %{"name" => "Older", "body" => "<p>a</p>"},
          created_by_id: user.id
        )

      {:ok, _newer} =
        Newsletter.create_notice(
          %{"name" => "Newer", "body" => "<p>b</p>"},
          created_by_id: user.id
        )

      past =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:second)

      Repo.update_all(
        from(n in Notice, where: n.id == ^older.id),
        set: [updated_at: past]
      )

      notices = Newsletter.list_notices()
      names = Enum.map(notices, & &1.name)

      assert Enum.find_index(names, &(&1 == "Newer")) <
               Enum.find_index(names, &(&1 == "Older"))

      listed = Enum.find(notices, &(&1.id == older.id))
      assert Ecto.assoc_loaded?(listed.creator)
      assert listed.creator.first_name == "Ada"
    end
  end

  describe "update_notice/2" do
    test "updates name and body" do
      {:ok, notice} =
        Newsletter.create_notice(%{"name" => "Old", "body" => "<p>old</p>"})

      assert {:ok, updated} =
               Newsletter.update_notice(notice, %{
                 "name" => "New",
                 "body" => "<p>new</p>"
               })

      assert updated.name == "New"
      assert updated.body =~ "new"
    end
  end

  describe "delete_notice/1" do
    test "deletes the notice" do
      {:ok, notice} =
        Newsletter.create_notice(%{"name" => "Gone", "body" => "<p>x</p>"})

      assert {:ok, _} = Newsletter.delete_notice(notice)

      assert_raise Ecto.NoResultsError, fn ->
        Newsletter.get_notice!(notice.id)
      end
    end
  end
end
