defmodule Ysc.AdminHelp.KnowledgeBaseTest do
  use ExUnit.Case, async: true

  alias Ysc.AdminHelp.KnowledgeBase

  test "index/0 lists documents with title and summary" do
    index = KnowledgeBase.index()

    assert index != []

    for entry <- index do
      assert %{slug: slug, title: title, summary: summary} = entry
      assert is_binary(slug) and slug != ""
      assert is_binary(title) and title != ""
      assert is_binary(summary) and summary != ""
      refute String.contains?(title, "---")
    end

    slugs = Enum.map(index, & &1.slug)
    assert slugs == Enum.uniq(slugs)
    assert "posts" in slugs
  end

  test "index_for_llm/1 renders one line per visible document for a role" do
    listing = KnowledgeBase.index_for_llm(:admin)

    assert length(String.split(listing, "\n")) == length(KnowledgeBase.index())
    assert listing =~ "- posts:"
  end

  test "index_for_llm/1 returns nothing when role is nil" do
    assert KnowledgeBase.index_for_llm(nil) == ""
  end

  test "index_for_llm/1 includes volunteer-relevant docs for volunteers" do
    volunteer_listing = KnowledgeBase.index_for_llm(:volunteer)

    assert volunteer_listing =~ "- roles-permissions:"
    assert volunteer_listing =~ "- posts:"
  end

  test "fetch/1 returns body without front matter" do
    assert {:ok, content} = KnowledgeBase.fetch("posts")
    refute String.starts_with?(content, "---")
    assert content =~ "#"
  end

  test "visible_to_role?/2 checks a single document without building the full index" do
    assert KnowledgeBase.visible_to_role?("posts", :volunteer)
    refute KnowledgeBase.visible_to_role?("nope-does-not-exist", :admin)
    refute KnowledgeBase.visible_to_role?("../config/runtime", :admin)
  end

  test "fetch/1 rejects unknown and unsafe slugs" do
    assert :error = KnowledgeBase.fetch("nope-does-not-exist")
    assert :error = KnowledgeBase.fetch("../config/runtime")
    assert :error = KnowledgeBase.fetch("../../etc/passwd")
    assert :error = KnowledgeBase.fetch(nil)
  end

  test "fetch_many/2 dedupes, skips unknown slugs, and caps at limit" do
    assert [{"posts", _}] =
             KnowledgeBase.fetch_many(["posts", "posts", "missing"])

    all_slugs = Enum.map(KnowledgeBase.index(), & &1.slug)
    assert length(KnowledgeBase.fetch_many(all_slugs, 3)) == 3
  end

  test "every document body is non-trivial" do
    for %{slug: slug} <- KnowledgeBase.index() do
      assert {:ok, content} = KnowledgeBase.fetch(slug)

      assert String.length(content) > 500,
             "knowledge base doc #{slug} is too thin"
    end
  end
end
