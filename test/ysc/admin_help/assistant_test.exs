defmodule Ysc.AdminHelp.AssistantTest.ScriptedClient do
  @moduledoc false

  # Test double for `Ysc.OpenRouter` that pops a queued response per call, so
  # a test can script exactly what each chat turn (finder / locate / clarify /
  # follow-up) returns. Responses live in the *process dictionary* of the
  # calling test process — `Assistant` calls this synchronously in-process
  # (no spawn), so `Process.put/2` from the test body is visible here.
  def do_chat(_messages, _config) do
    case Process.get(:scripted_responses) do
      [next | rest] ->
        Process.put(:scripted_responses, rest)
        next

      _ ->
        {:ok, Jason.encode!(%{"answer" => "fallback", "suggested_step" => nil})}
    end
  end
end

defmodule Ysc.AdminHelp.AssistantTest do
  # Mutates the global :open_router app env — must not run concurrently with
  # other tests that read or mutate it.
  use ExUnit.Case, async: false

  alias Ysc.AdminHelp.Assistant
  alias Ysc.AdminHelp.AssistantTest.ScriptedClient
  alias Ysc.AdminHelpRateLimit
  alias YscWeb.AdminHelp.Guides.PublishPost
  alias YscWeb.AdminHelp.Registry

  setup do
    prev_open_router = Application.get_env(:ysc, :open_router)
    prev_client = Application.get_env(:ysc, :open_router_client)

    Application.put_env(:ysc, :open_router,
      api_key: "test-key",
      model: "test-model"
    )

    Application.put_env(:ysc, :open_router_client, Ysc.OpenRouter.Mock)

    on_exit(fn ->
      if prev_open_router do
        Application.put_env(:ysc, :open_router, prev_open_router)
      else
        Application.delete_env(:ysc, :open_router)
      end

      if prev_client do
        Application.put_env(:ysc, :open_router_client, prev_client)
      else
        Application.delete_env(:ysc, :open_router_client)
      end
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

  # ---------------------------------------------------------------------------
  # Rate limiting
  # ---------------------------------------------------------------------------

  describe "rate limiting" do
    test "find_guide/3 returns rate_limited when user_id is nil" do
      assert {:error, :rate_limited} =
               Assistant.find_guide("send newsletter", :volunteer, nil)
    end

    test "clarify_step/5 returns rate_limited when user_id is nil" do
      assert {:error, :rate_limited} =
               Assistant.clarify_step(PublishPost, 1, "help", :volunteer, nil)
    end

    test "find_guide/3 returns rate_limited once the per-user limit is exhausted" do
      user_id = "rate-limit-user-#{System.unique_integer([:positive])}"

      for _ <- 1..10, do: assert(:ok == AdminHelpRateLimit.check(user_id))

      assert {:error, :rate_limited} =
               Assistant.find_guide("send newsletter", :volunteer, user_id)
    end
  end

  # ---------------------------------------------------------------------------
  # Transport / parsing failures
  # ---------------------------------------------------------------------------

  describe "chat transport and parsing failures" do
    test "find_guide/3 returns not_configured when the API key is blank" do
      Application.put_env(:ysc, :open_router, api_key: "", model: "test-model")

      assert {:error, :not_configured} =
               Assistant.find_guide("send newsletter", :volunteer, uid())
    end

    test "find_guide/3 propagates a generic chat error" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)
      Process.put(:scripted_responses, [{:error, :boom}])

      assert {:error, :boom} =
               Assistant.find_guide("send newsletter", :volunteer, uid())
    end

    test "find_guide/3 returns invalid_json for a non-JSON reply" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)
      Process.put(:scripted_responses, [{:ok, "not json at all"}])

      assert {:error, :invalid_json} =
               Assistant.find_guide("send newsletter", :volunteer, uid())
    end

    test "find_guide/3 returns invalid_json when the finder reply has no explanation" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)

      Process.put(:scripted_responses, [
        {:ok, Jason.encode!(%{"guide_slug" => "newsletters/send"})}
      ])

      assert {:error, :invalid_json} =
               Assistant.find_guide("send newsletter", :volunteer, uid())
    end

    test "clarify_step/5 returns invalid_json when the reply has no answer" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)

      Process.put(:scripted_responses, [
        {:ok, Jason.encode!(%{"suggested_step" => 1})}
      ])

      assert {:error, :invalid_json} =
               Assistant.clarify_step(PublishPost, 1, "help", :volunteer, uid())
    end
  end

  # ---------------------------------------------------------------------------
  # Finder result validation
  # ---------------------------------------------------------------------------

  describe "finder result validation" do
    test "accepts a valid, allowed guide slug even at low confidence" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)

      Process.put(:scripted_responses, [
        {:ok,
         Jason.encode!(%{
           "guide_slug" => "newsletters/send",
           "explanation" => "Might help.",
           "confidence" => "low"
         })},
        {:ok, Jason.encode!(%{"step" => nil, "highlight" => nil})}
      ])

      assert {:ok, %{guide_slug: "newsletters/send", confidence: :low}} =
               Assistant.find_guide("newsletter stuff", :volunteer, uid())
    end

    test "drops an unknown guide_slug that isn't in the registry" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)

      Process.put(:scripted_responses, [
        {:ok,
         Jason.encode!(%{
           "guide_slug" => "not-a-real-guide",
           "explanation" => "Sure!",
           "confidence" => "high"
         })}
      ])

      assert {:ok, %{guide_slug: nil, step: nil, highlight: nil}} =
               Assistant.find_guide("gibberish", :volunteer, uid())
    end
  end

  # ---------------------------------------------------------------------------
  # Step locating
  # ---------------------------------------------------------------------------

  describe "step locating" do
    test "falls back to nil step/highlight when the locate turn fails to parse" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)

      Process.put(:scripted_responses, [
        {:ok,
         Jason.encode!(%{
           "guide_slug" => "newsletters/send",
           "explanation" => "Use this guide.",
           "confidence" => "high"
         })},
        {:ok, "not valid json"}
      ])

      assert {:ok, %{guide_slug: "newsletters/send", step: nil, highlight: nil}} =
               Assistant.find_guide("send newsletter", :volunteer, uid())
    end

    test "accepts a step number sent as a string" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)

      Process.put(:scripted_responses, [
        {:ok,
         Jason.encode!(%{
           "guide_slug" => "newsletters/send",
           "explanation" => "Use this guide.",
           "confidence" => "high"
         })},
        {:ok,
         Jason.encode!(%{
           "step" => "2",
           "highlight" =>
             "A real copy of the email goes to **your own address**"
         })}
      ])

      assert {:ok, %{step: 2, highlight: highlight}} =
               Assistant.find_guide("test the email first", :volunteer, uid())

      assert highlight == "A real copy of the email goes to your own address"
    end

    test "drops a highlight that is blank after stripping markdown markers" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)

      Process.put(:scripted_responses, [
        {:ok,
         Jason.encode!(%{
           "guide_slug" => "newsletters/send",
           "explanation" => "Use this guide.",
           "confidence" => "high"
         })},
        {:ok, Jason.encode!(%{"step" => 2, "highlight" => "**"})}
      ])

      assert {:ok, %{step: 2, highlight: nil}} =
               Assistant.find_guide("send newsletter", :volunteer, uid())
    end
  end

  # ---------------------------------------------------------------------------
  # clarify_step suggested_step validation
  # ---------------------------------------------------------------------------

  describe "clarify_step/5 suggested_step validation" do
    test "accepts a suggested_step sent as a string" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)

      Process.put(:scripted_responses, [
        {:ok,
         Jason.encode!(%{
           "answer" => "Add a featured image first.",
           "suggested_step" => "3"
         })}
      ])

      assert {:ok, %{suggested_step: 3}} =
               Assistant.clarify_step(
                 PublishPost,
                 2,
                 "Why can't I publish?",
                 :volunteer,
                 uid()
               )
    end
  end

  # ---------------------------------------------------------------------------
  # Reference document lookup
  # ---------------------------------------------------------------------------

  describe "reference document follow-up" do
    test "answers with an explicit note when every requested doc is unknown" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)

      Process.put(:scripted_responses, [
        {:ok, Jason.encode!(%{"read_docs" => ["totally-fake-doc"]})},
        {:ok,
         Jason.encode!(%{"answer" => "no docs found", "suggested_step" => nil})}
      ])

      assert {:ok, %{answer: "no docs found"}} =
               Assistant.clarify_step(
                 PublishPost,
                 1,
                 "obscure question",
                 :volunteer,
                 uid()
               )
    end

    test "skips reference docs for a role outside admin/volunteer" do
      Application.put_env(:ysc, :open_router_client, ScriptedClient)

      Process.put(:scripted_responses, [
        {:ok, Jason.encode!(%{"read_docs" => ["posts"]})},
        {:ok,
         Jason.encode!(%{
           "answer" => "no docs for this role",
           "suggested_step" => nil
         })}
      ])

      assert {:ok, %{answer: "no docs for this role"}} =
               Assistant.clarify_step(
                 PublishPost,
                 1,
                 "obscure question",
                 :guest,
                 uid()
               )
    end
  end

  defp uid, do: "user-#{System.unique_integer([:positive])}"
end
