defmodule Ysc.AdminHelp.AssistantTest do
  # Mutates the global :open_router app env — must not run concurrently with
  # other tests that read or mutate it.
  use ExUnit.Case, async: false

  alias Ysc.AdminHelp.Assistant
  alias YscWeb.AdminHelp.Guides.PublishPost
  alias YscWeb.AdminHelp.Registry

  setup do
    Application.put_env(:ysc, :open_router,
      api_key: "test-key",
      model: "test-model"
    )

    Application.put_env(:ysc, :open_router_client, Ysc.OpenRouter.Mock)

    on_exit(fn ->
      Application.delete_env(:ysc, :open_router)
      Application.delete_env(:ysc, :open_router_client)
    end)

    :ok
  end

  test "enabled?/0 when api key is set" do
    assert Assistant.enabled?()
  end

  test "find_guide/2 returns validated slug" do
    assert {:ok, %{guide_slug: "newsletters/send", explanation: explanation}} =
             Assistant.find_guide("send newsletter", :volunteer, "user-1")

    assert explanation != ""
    assert Registry.valid_slug?("newsletters/send")
  end

  test "find_guide/2 pinpoints the step and a verified highlight quote" do
    # The mock locate stage answers step 2 with a quote containing ** markers;
    # validation strips them and verifies the quote exists in that step's body.
    assert {:ok,
            %{guide_slug: "newsletters/send", step: 2, highlight: highlight}} =
             Assistant.find_guide("test the email first", :volunteer, "user-1")

    assert highlight == "A real copy of the email goes to your own address"

    step = YscWeb.AdminHelp.Guides.SendNewsletter.steps() |> Enum.at(1)
    assert String.replace(step.body, "**", "") =~ highlight
  end

  test "clarify_step/4 returns answer" do
    assert {:ok, %{answer: answer, suggested_step: 3}} =
             Assistant.clarify_step(
               PublishPost,
               2,
               "Why can't I publish?",
               :volunteer,
               "user-1"
             )

    assert String.contains?(answer, "featured image")
  end

  test "clarify_step/4 loads knowledge base documents on the fly" do
    # The mock requests ["posts", "does-not-exist"] when the question
    # mentions "deep dive", then answers with the slugs it received.
    assert {:ok, %{answer: answer}} =
             Assistant.clarify_step(
               PublishPost,
               1,
               "deep dive into post settings",
               :volunteer,
               "user-1"
             )

    assert answer =~ "Answer grounded in loaded docs: posts"
    refute answer =~ "does-not-exist"
  end
end
