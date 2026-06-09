defmodule YscWeb.AdminHelp.Ghost.RegistryTest do
  use ExUnit.Case, async: true

  alias YscWeb.AdminHelp.Ghost.Registry

  test "all preview slugs are fetchable" do
    for slug <- Registry.all() do
      assert {:ok, %{slug: ^slug}} = Registry.fetch(slug)
    end
  end

  test "print_image_path/1 resolves ghost slugs to static fallbacks" do
    assert Registry.print_image_path("ghost:posts-list") =~
             "/images/admin-help/posts-list"

    assert Registry.print_image_path("/images/foo.png") == "/images/foo.png"
  end
end
