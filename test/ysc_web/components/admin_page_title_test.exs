defmodule YscWeb.AdminPageTitleTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_page_title/1" do
    test "default variant renders h1 with semibold admin title classes" do
      html =
        rendered_to_string(~H"""
        <.admin_page_title>Dashboard</.admin_page_title>
        """)

      assert html =~
               ~s(<h1 class="text-2xl font-semibold leading-8 text-zinc-800")

      assert html =~ "Dashboard"
    end

    test "level 2 renders h2" do
      html =
        rendered_to_string(~H"""
        <.admin_page_title level={2}>Section</.admin_page_title>
        """)

      assert html =~
               ~s(<h2 class="text-2xl font-semibold leading-8 text-zinc-800")

      assert html =~ "Section"
    end

    test "emphasis variant uses bold zinc-900 styling" do
      html =
        rendered_to_string(~H"""
        <.admin_page_title level={2} variant={:emphasis}>Review</.admin_page_title>
        """)

      assert html =~ ~s(<h2 class="text-2xl font-bold text-zinc-900")
      assert html =~ "Review"
    end

    test "merges extra classes onto the title" do
      html =
        rendered_to_string(~H"""
        <.admin_page_title level={2} class="mb-4">Modal title</.admin_page_title>
        """)

      assert html =~ "mb-4"
    end
  end
end
