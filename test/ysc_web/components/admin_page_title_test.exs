defmodule YscWeb.AdminPageTitleTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_page_title/1" do
    test "default variant renders h1 with admin title type token" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_title>Dashboard</.admin_page_title>
        """)

      assert html =~
               ~s(<h1 class="text-2xl text-zinc-800 type-display")

      assert html =~ "Dashboard"
    end

    test "level 2 renders h2" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_title level={2}>Section</.admin_page_title>
        """)

      assert html =~
               ~s(<h2 class="text-2xl text-zinc-800 type-display")

      assert html =~ "Section"
    end

    test "emphasis variant uses zinc-900 styling" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_title level={2} variant={:emphasis}>Review</.admin_page_title>
        """)

      assert html =~ ~s(<h2 class="text-2xl text-zinc-900 type-display")
      assert html =~ "Review"
    end

    test "merges extra classes onto the title" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_title level={2} class="mb-4">Modal title</.admin_page_title>
        """)

      assert html =~ "mb-4"
    end

    test "renders optional subtitle below the title" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_title subtitle="Manage active entitlements.">
          Benefits
        </.admin_page_title>
        """)

      assert html =~ "Benefits"
      assert html =~ "Manage active entitlements."
      assert html =~ ~s(<p class="text-sm text-zinc-500 mt-1">)
    end

    test "does not render a help link without help_topic" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_title>Dashboard</.admin_page_title>
        """)

      refute html =~ "admin-help-link"
      refute html =~ "flex items-center gap-2"
    end

    test "renders a help link beside the title when help_topic is set" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_title
          help_topic="posts/publish"
          help_label="How to publish a post"
          help_role={:admin}
        >
          Posts
        </.admin_page_title>
        """)

      assert html =~ ~s(class="flex items-center gap-2")

      assert html =~
               ~s(<h1 class="text-2xl text-zinc-800 type-display")

      assert html =~ "Posts"
      assert html =~ ~s(id="admin-help-link-posts-publish")
      assert html =~ ~s(href="/admin/help/posts%2Fpublish")
      assert html =~ "How to publish a post"
    end

    test "keeps the subtitle below the title and help link" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_title
          help_topic="media/upload"
          help_label="Media help"
          subtitle="All uploaded images."
        >
          Media Library
        </.admin_page_title>
        """)

      assert html =~ "Media Library"
      assert html =~ ~s(id="admin-help-link-media-upload")
      assert html =~ "All uploaded images."
      assert html =~ ~s(<p class="text-sm text-zinc-500 mt-1">)
    end
  end

  describe "admin_page_header/1" do
    test "renders the title inside the index header layout" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_header>Settings</.admin_page_header>
        """)

      assert html =~ "<header"
      assert html =~ "flex flex-wrap items-start justify-between gap-4 py-6"
      assert html =~ ~s(<h1 class="text-2xl text-zinc-800 type-display")
      assert html =~ "Settings"
      refute html =~ "flex items-center gap-3 shrink-0"
    end

    test "renders actions beside the title" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_header>
          Posts
          <:actions>
            <a id="admin-posts-new-post" href="/admin/posts/new">New Post</a>
          </:actions>
        </.admin_page_header>
        """)

      assert html =~ "Posts"
      assert html =~ ~s(id="admin-posts-new-post")
      assert html =~ "flex items-center gap-3 shrink-0"
    end

    test "forwards subtitle and help link to admin_page_title" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_header
          id="admin-events-header"
          help_topic="events/create"
          help_label="How to create an event"
          help_role={:admin}
          subtitle="Upcoming, drafts, and past events."
        >
          Events
        </.admin_page_header>
        """)

      assert html =~ ~s(id="admin-events-header")
      assert html =~ "Events"
      assert html =~ "Upcoming, drafts, and past events."
      assert html =~ ~s(id="admin-help-link-events-create")
      assert html =~ ~s(href="/admin/help/events%2Fcreate")
      assert html =~ "How to create an event"
    end

    test "merges extra classes onto the header" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_page_header class="mb-2">Users</.admin_page_header>
        """)

      assert html =~ "mb-2"
      assert html =~ "py-6"
    end
  end
end
