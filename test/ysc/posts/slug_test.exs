defmodule Ysc.Posts.SlugTest do
  use Ysc.DataCase, async: true

  alias Ysc.Posts.Slug

  describe "from_title/1" do
    test "slugifies a title" do
      assert Slug.from_title("Hello World!") == "hello-world"
    end

    test "uses default slug for empty title" do
      assert Slug.from_title("") == "new-untitled-post"
    end

    test "uses default slug for whitespace-only title" do
      assert Slug.from_title("   ") == "new-untitled-post"
    end

    test "slugifies the default new post title" do
      assert Slug.from_title(Slug.default_title()) == "new-untitled-post"
    end
  end

  describe "title_or_default/1" do
    test "returns default for blank titles" do
      assert Slug.title_or_default("") == Slug.default_title()
      assert Slug.title_or_default("   ") == Slug.default_title()
      assert Slug.title_or_default(nil) == Slug.default_title()
    end

    test "preserves non-blank titles" do
      assert Slug.title_or_default("My Post") == "My Post"
      assert Slug.title_or_default("  My Post  ") == "My Post"
    end
  end

  describe "unique/1" do
    import Ysc.AccountsFixtures

    alias Ysc.Posts

    setup do
      %{author: user_fixture(%{role: "admin"})}
    end

    test "returns the slug when unused" do
      assert Slug.unique("unused-slug-#{System.unique_integer()}") =~
               "unused-slug"
    end

    test "appends a suffix when slug exists", %{author: author} do
      base = "collision-#{System.unique_integer()}"

      {:ok, _} =
        Posts.create_post(
          %{"title" => "T", "url_name" => base, "state" => "draft"},
          author
        )

      assert Slug.unique(base) == "#{base}-2"
    end
  end
end
