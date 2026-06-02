defmodule Ysc.Posts.SlugTest do
  use Ysc.DataCase, async: true

  alias Ysc.Posts.Slug

  describe "default_title/0" do
    test "returns the new post placeholder title" do
      assert Slug.default_title() == "New Untitled Post"
    end
  end

  describe "blank_title?/1" do
    test "returns true for non-string values" do
      assert Slug.blank_title?(nil)
      assert Slug.blank_title?(:not_a_title)
      assert Slug.blank_title?(123)
    end
  end

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

    test "uses default slug for non-string titles" do
      assert Slug.from_title(nil) == "new-untitled-post"
      assert Slug.from_title(123) == "new-untitled-post"
    end

    test "uses default slug when punctuation strips entire title" do
      assert Slug.from_title("!!!") == "new-untitled-post"
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

    test "returns default for non-string values" do
      assert Slug.title_or_default(:not_a_title) == Slug.default_title()
      assert Slug.title_or_default(123) == Slug.default_title()
    end
  end

  describe "from_title_unique/1" do
    import Ysc.AccountsFixtures

    alias Ysc.Posts

    setup do
      %{author: user_fixture(%{role: "admin"})}
    end

    test "returns a unique slug when the base slug is taken", %{author: author} do
      base = Slug.from_title("Hello World")

      {:ok, _} =
        Posts.create_post(
          %{"title" => "Existing", "url_name" => base, "state" => "draft"},
          author
        )

      assert Slug.from_title_unique("Hello World!") == "#{base}-2"
    end

    test "returns the base slug when unused" do
      slug = "unused-unique-#{System.unique_integer()}"
      assert Slug.from_title_unique(slug) == Slug.from_title(slug)
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
