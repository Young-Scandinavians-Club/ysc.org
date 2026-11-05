defmodule Ysc.Media.PosterReviewTest do
  # Mutates the global :open_router app env, so it must not run concurrently
  # with other tests that read it.
  use ExUnit.Case, async: false

  alias Ysc.Media.Image, as: MediaImage
  alias Ysc.Media.PosterReview
  alias Ysc.Test.CapturingOpenRouterClient

  @png File.read!(Path.expand("../../support/fixtures/tiny.png", __DIR__))

  setup do
    prev_open_router = Application.get_env(:ysc, :open_router)
    prev_client = Application.get_env(:ysc, :open_router_client)

    Application.put_env(:ysc, :open_router,
      api_key: "test-key",
      model: "test-text-model",
      vision_model: "test-vision-model"
    )

    Application.put_env(:ysc, :open_router_client, CapturingOpenRouterClient)

    on_exit(fn ->
      restore(:open_router, prev_open_router)
      restore(:open_router_client, prev_client)
    end)

    Req.Test.set_req_test_from_context(%{async: false})
    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:ysc, key)
  defp restore(key, value), do: Application.put_env(:ysc, key, value)

  defp image do
    %MediaImage{
      id: "01TESTIMAGE",
      raw_image_path: "https://media.example.test/raw.png",
      optimized_image_path: "https://media.example.test/optimized.png",
      width: 1920,
      height: 1080
    }
  end

  defp serve_image(body \\ @png, status \\ 200) do
    Req.Test.stub(PosterReview, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("image/png")
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  defp reply(json), do: Process.put(:capturing_response, {:ok, json})

  describe "review/1" do
    test "sends the downscaled image to the vision model and returns findings" do
      serve_image()

      reply(
        Jason.encode!(%{
          "findings" => [
            %{"rule" => "embedded_text", "detail" => "A flyer with dates."},
            %{"rule" => "collage_or_border", "detail" => "Two photos."}
          ]
        })
      )

      assert {:ok, findings} = PosterReview.review(image())

      assert findings == [
               %{rule: :embedded_text, detail: "A flyer with dates."},
               %{rule: :collage_or_border, detail: "Two photos."}
             ]

      assert_received {:chat, messages, config}
      assert config[:model] == "test-vision-model"

      assert [%{role: "system"}, %{role: "user", content: parts}] = messages

      assert [
               %{type: "text"},
               %{
                 type: "image_url",
                 image_url: %{url: "data:image/jpeg;base64," <> b64}
               }
             ] = parts

      assert {:ok, _jpeg} = Base.decode64(b64)
    end

    test "prefers the optimized path over the raw upload" do
      test_pid = self()

      Req.Test.stub(PosterReview, fn conn ->
        send(test_pid, {:fetched, conn.request_path})

        conn
        |> Plug.Conn.put_resp_content_type("image/png")
        |> Plug.Conn.send_resp(200, @png)
      end)

      reply(~s({"findings": []}))

      assert {:ok, []} = PosterReview.review(image())
      assert_received {:fetched, "/optimized.png"}
    end

    test "returns no findings when the model passes the image" do
      serve_image()
      reply(~s({"findings": []}))

      assert {:ok, []} = PosterReview.review(image())
    end

    test "falls back to the default vision model when none is configured" do
      Application.put_env(:ysc, :open_router, api_key: "test-key")
      serve_image()
      reply(~s({"findings": []}))

      assert {:ok, []} = PosterReview.review(image())
      assert_received {:chat, _messages, config}
      assert config[:model] == "google/gemini-2.5-flash"
    end

    test "reports a failed download without calling the model" do
      serve_image("nope", 404)

      assert {:error, :download_failed} = PosterReview.review(image())
      refute_received {:chat, _, _}
    end

    test "reports bytes that are not an image without calling the model" do
      serve_image("definitely not an image")

      assert {:error, :unreadable_image} = PosterReview.review(image())
      refute_received {:chat, _, _}
    end

    test "passes provider errors through" do
      serve_image()
      Process.put(:capturing_response, {:error, :rate_limited})

      assert {:error, :rate_limited} = PosterReview.review(image())
    end

    test "returns :not_configured without an API key" do
      Application.put_env(:ysc, :open_router, api_key: "")
      serve_image()

      assert {:error, :not_configured} = PosterReview.review(image())
    end

    test "errors when the image has no path" do
      assert {:error, :no_image_path} =
               PosterReview.review(%MediaImage{
                 raw_image_path: nil,
                 optimized_image_path: nil
               })
    end
  end

  describe "available?/0" do
    test "is true only with a non-blank API key" do
      assert PosterReview.available?()

      Application.put_env(:ysc, :open_router, api_key: "  ")
      refute PosterReview.available?()

      Application.put_env(:ysc, :open_router, api_key: nil)
      refute PosterReview.available?()

      Application.delete_env(:ysc, :open_router)
      refute PosterReview.available?()
    end
  end

  describe "parse_findings/1" do
    test "accepts JSON wrapped in a code fence" do
      raw = """
      ```json
      {"findings": [{"rule": "not_a_photograph", "detail": "Clipart."}]}
      ```
      """

      assert {:ok, [%{rule: :not_a_photograph, detail: "Clipart."}]} =
               PosterReview.parse_findings(raw)
    end

    test "ignores unknown rules, malformed entries and duplicates" do
      raw =
        Jason.encode!(%{
          "findings" => [
            %{"rule" => "made_up_rule", "detail" => "x"},
            %{"detail" => "no rule"},
            "garbage",
            %{"rule" => "embedded_text", "detail" => "first"},
            %{"rule" => "embedded_text", "detail" => "second"}
          ]
        })

      assert {:ok, [%{rule: :embedded_text, detail: "first"}]} =
               PosterReview.parse_findings(raw)
    end

    test "trims details, caps their length and tolerates a missing detail" do
      long = String.duplicate("a", 500)

      raw =
        Jason.encode!(%{
          "findings" => [
            %{"rule" => "embedded_text", "detail" => "  " <> long},
            %{"rule" => "off_center_subject"}
          ]
        })

      assert {:ok, [first, second]} = PosterReview.parse_findings(raw)
      assert String.length(first.detail) == 200
      assert second == %{rule: :off_center_subject, detail: ""}
    end

    test "rejects replies that are not the expected JSON" do
      for raw <- ["", "looks fine to me", ~s({"findings": "none"}), "[1, 2]"] do
        assert {:error, :invalid_response} = PosterReview.parse_findings(raw)
      end
    end
  end

  describe "to_data_url/1" do
    test "downscales large images to the review width" do
      {:ok, big} = Image.new(3000, 1688, color: [200, 30, 30])
      {:ok, png} = Image.write(big, :memory, suffix: ".png")

      assert {:ok, "data:image/jpeg;base64," <> b64} =
               PosterReview.to_data_url(png)

      {:ok, jpeg} = Base.decode64(b64)
      {:ok, decoded} = Image.from_binary(jpeg)
      assert Image.width(decoded) == 1024
    end

    test "does not upscale small images" do
      {:ok, small} = Image.new(200, 100, color: [0, 0, 255])
      {:ok, png} = Image.write(small, :memory, suffix: ".png")

      assert {:ok, "data:image/jpeg;base64," <> b64} =
               PosterReview.to_data_url(png)

      {:ok, decoded} = Image.from_binary(Base.decode64!(b64))
      assert Image.width(decoded) == 200
    end

    test "rejects data that is not an image" do
      assert {:error, :unreadable_image} = PosterReview.to_data_url("nope")
    end
  end

  describe "describe/1" do
    test "has advice for every rule" do
      for rule <- PosterReview.rules() do
        assert {title, advice} = PosterReview.describe(rule)
        assert title != ""
        assert advice != ""
      end
    end
  end
end
