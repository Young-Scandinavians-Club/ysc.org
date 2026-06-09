defmodule YscWeb.AdminHelp.RegistryTest do
  use ExUnit.Case, async: true

  alias YscWeb.AdminHelp.Registry

  test "all guides have unique slugs and non-empty steps" do
    slugs =
      Registry.all()
      |> Enum.map(& &1.slug())

    assert length(slugs) == length(Enum.uniq(slugs))

    for mod <- Registry.all() do
      assert mod.steps() != []
      assert is_binary(mod.title())
      assert is_binary(mod.summary())
    end
  end

  test "fetch/1 returns guide modules for known slugs" do
    assert {:ok, _} = Registry.fetch("posts/publish")
    assert {:ok, _} = Registry.fetch("getting-started")
    assert :error = Registry.fetch("unknown/guide")
  end

  test "guides_for_role includes content guides for volunteers" do
    slugs =
      Registry.guides_for_role(:volunteer)
      |> Enum.map(& &1.slug())

    assert "posts/publish" in slugs
    assert "day-of/scanner" in slugs
    assert "getting-started/roles" in slugs
  end

  test "fetch_for_role returns error for unknown slugs" do
    assert {:ok, _} = Registry.fetch_for_role("posts/publish", :volunteer)
    assert :error = Registry.fetch_for_role("not/a/guide", :volunteer)
  end

  test "accessible? reflects guide audience" do
    assert Registry.accessible?("getting-started/roles", :volunteer)
    assert Registry.accessible?("getting-started/roles", :admin)
    refute Registry.accessible?("not/a/guide", :volunteer)
  end
end
