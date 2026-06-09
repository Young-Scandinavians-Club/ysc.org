defmodule Ysc.AdminHelp.LiveExamplesTest do
  # Mutates the global :open_router app env — must not run concurrently with
  # other tests that read or mutate it.
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.AdminHelp.Assistant
  alias Ysc.AdminHelp.LiveExamples
  alias Ysc.Newsletter
  alias Ysc.Posts.Post
  alias YscWeb.AdminHelp.Guides.PublishPost

  defp create_post(attrs) do
    author = user_fixture()

    default_attrs = %{
      title: "Test Post #{System.unique_integer()}",
      raw_body: "<p>Body</p>",
      url_name: "test-post-#{System.unique_integer()}",
      state: :published,
      published_on: DateTime.utc_now(),
      user_id: author.id
    }

    {:ok, post} =
      %Post{}
      |> Post.new_post_changeset(Map.merge(default_attrs, attrs))
      |> Repo.insert()

    post
  end

  test "index_for_llm/0 lists all snapshots with live- slugs" do
    listing = LiveExamples.index_for_llm()

    for %{slug: slug} <- LiveExamples.index() do
      assert String.starts_with?(slug, "live-")
      assert listing =~ slug
    end
  end

  test "live-recent-posts includes real post titles and public URLs" do
    post = create_post(%{title: "Midsummer Recap", url_name: "midsummer-recap"})

    draft =
      create_post(%{title: "Half-written", state: :draft, published_on: nil})

    assert {:ok, content} = LiveExamples.fetch("live-recent-posts")
    assert content =~ ~s("Midsummer Recap")
    assert content =~ "/posts/#{post.url_name}"
    assert content =~ ~s("#{draft.title}" — draft)
    refute content =~ "@"
  end

  test "live-recent-events includes real events with state and registration" do
    event_fixture(%{title: "Crayfish Party", max_attendees: 80})

    assert {:ok, content} = LiveExamples.fetch("live-recent-events")
    assert content =~ ~s("Crayfish Party")
    assert content =~ "max 80 attendees"
    assert content =~ "published"
  end

  test "live-recent-newsletters includes real editions with status" do
    {:ok, _edition} =
      Newsletter.create_edition(%{
        "title" => "June News",
        "subject" => "What's on in June"
      })

    assert {:ok, content} = LiveExamples.fetch("live-recent-newsletters")
    assert content =~ ~s("June News")
    assert content =~ ~s(subject: "What's on in June")
    assert content =~ "draft"
  end

  test "fetch/1 rejects unknown slugs" do
    assert :error = LiveExamples.fetch("live-subscriber-emails")
    assert :error = LiveExamples.fetch("posts")
  end

  test "assistant loads live data on the fly" do
    Application.put_env(:ysc, :open_router,
      api_key: "test-key",
      model: "test-model"
    )

    Application.put_env(:ysc, :open_router_client, Ysc.OpenRouter.Mock)

    on_exit(fn ->
      Application.delete_env(:ysc, :open_router)
      Application.delete_env(:ysc, :open_router_client)
    end)

    create_post(%{title: "Live Example Post"})

    # The mock requests ["live-recent-posts"] when the question mentions
    # "real examples", then answers with the slugs it received.
    assert {:ok, %{answer: answer}} =
             Assistant.clarify_step(
               PublishPost,
               1,
               "show me real examples",
               :volunteer,
               "user-1"
             )

    assert answer =~ "Answer grounded in loaded docs: live-recent-posts"
  end
end
