defmodule YscWeb.SEOTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.TestDataFactory

  alias Ysc.Media
  alias Ysc.Posts
  alias Ysc.Repo
  alias YscWeb.SEO

  describe "absolute_url/1" do
    test "prefixes the site origin" do
      assert SEO.absolute_url("/events/abc") ==
               YscWeb.Endpoint.url() <> "/events/abc"
    end
  end

  describe "absolute_image_url/1" do
    test "returns nil for blank values" do
      assert SEO.absolute_image_url(nil) == nil
      assert SEO.absolute_image_url("") == nil
    end

    test "keeps absolute http(s) URLs" do
      assert SEO.absolute_image_url("https://cdn.example.com/a.jpg") ==
               "https://cdn.example.com/a.jpg"

      assert SEO.absolute_image_url("http://cdn.example.com/a.jpg") ==
               "http://cdn.example.com/a.jpg"
    end

    test "makes relative paths absolute" do
      assert SEO.absolute_image_url("/uploads/a.jpg") ==
               YscWeb.Endpoint.url() <> "/uploads/a.jpg"

      assert SEO.absolute_image_url("uploads/a.jpg") ==
               YscWeb.Endpoint.url() <> "/uploads/a.jpg"
    end
  end

  describe "truncate_description/1" do
    test "returns nil for blank input" do
      assert SEO.truncate_description(nil) == nil
      assert SEO.truncate_description("   ") == nil
    end

    test "returns short text unchanged" do
      assert SEO.truncate_description("Hello world") == "Hello world"
    end

    test "truncates long text to 160 characters with ellipsis" do
      long = String.duplicate("a", 200)
      result = SEO.truncate_description(long)

      assert String.length(result) == 160
      assert String.ends_with?(result, "…")
    end
  end

  describe "og_image_or_default/1" do
    test "falls back to the YSC logo" do
      assert SEO.og_image_or_default(nil) == SEO.default_og_image_url()
      assert SEO.og_image_or_default("") == SEO.default_og_image_url()
      assert SEO.og_image_or_default("   ") == SEO.default_og_image_url()

      assert SEO.og_image_or_default("https://cdn.example.com/cover.jpg") ==
               "https://cdn.example.com/cover.jpg"
    end
  end

  describe "twitter_card_for_image/1" do
    test "uses summary for missing or default logo images" do
      assert SEO.twitter_card_for_image(SEO.og_image_or_default(nil)) ==
               "summary"

      assert SEO.twitter_card_for_image(SEO.og_image_or_default("")) ==
               "summary"

      assert SEO.twitter_card_for_image(SEO.og_image_or_default("   ")) ==
               "summary"

      assert SEO.twitter_card_for_image(SEO.default_og_image_url()) == "summary"
    end

    test "uses summary_large_image for custom photos" do
      assert SEO.twitter_card_for_image("https://cdn.example.com/cover.jpg") ==
               "summary_large_image"
    end
  end

  describe "assigns_for_post/1" do
    test "uses title, truncated plain-text description, featured image, and canonical URL" do
      author = user_fixture()

      {:ok, image} =
        %Media.Image{user_id: author.id}
        |> Media.Image.add_image_changeset(%{
          title: "Hero",
          raw_image_path: "/uploads/post_raw.jpg",
          optimized_image_path: "/uploads/post_opt.jpg",
          thumbnail_path: "/uploads/post_thumb.jpg"
        })
        |> Repo.insert()

      {:ok, post} =
        %Posts.Post{}
        |> Posts.Post.new_post_changeset(%{
          title: "Club Picnic",
          url_name: "club-picnic",
          raw_body: "<p>Ignored when preview exists</p>",
          preview_text: "Join us for the annual picnic in the park.",
          state: :published,
          published_on: DateTime.utc_now(),
          user_id: author.id,
          image_id: image.id,
          comment_count: 0
        })
        |> Repo.insert()

      post = Repo.preload(post, :featured_image)
      seo = SEO.assigns_for_post(post)

      assert seo.page_title == "Club Picnic"

      assert seo.meta_description ==
               "Join us for the annual picnic in the park."

      assert seo.og_type == "article"
      assert seo.og_url == YscWeb.Endpoint.url() <> "/posts/club-picnic"
      assert seo.canonical_url == seo.og_url

      assert seo.og_image ==
               YscWeb.Endpoint.url() <> "/uploads/post_opt.jpg"
    end

    test "falls back to YSC logo and description when missing" do
      author = user_fixture()

      {:ok, post} =
        %Posts.Post{}
        |> Posts.Post.new_post_changeset(%{
          title: "Empty Body",
          url_name: "empty-body",
          raw_body: "",
          preview_text: nil,
          state: :published,
          published_on: DateTime.utc_now(),
          user_id: author.id,
          comment_count: 0
        })
        |> Repo.insert()

      post = Repo.preload(post, :featured_image)
      seo = SEO.assigns_for_post(post)

      assert seo.meta_description =~ "Young Scandinavians Club news feed"

      assert seo.og_image == SEO.default_og_image_url()
      assert SEO.default_og_image_path() == "/images/ysc_logo.webp"
    end
  end

  describe "assigns_for_event/1" do
    test "uses title, description, cover image, and canonical URL" do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{
            title: "Midsummer Dance",
            description: "An evening of Swedish folk dancing."
          }
        )

      event = Repo.preload(event, :cover_image)
      seo = SEO.assigns_for_event(event)

      assert seo.page_title == "Midsummer Dance"
      assert seo.meta_description == "An evening of Swedish folk dancing."
      assert seo.og_type == "website"
      assert seo.og_url == YscWeb.Endpoint.url() <> "/events/#{event.id}"
      assert seo.canonical_url == seo.og_url
      assert seo.og_image =~ "/uploads/test_image_optimized.jpg"
    end

    test "falls back to default description when event description is blank" do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "No Desc", description: nil}
        )

      event = Repo.preload(event, :cover_image)
      seo = SEO.assigns_for_event(event)

      assert seo.meta_description =~ "View event details"
    end
  end
end
