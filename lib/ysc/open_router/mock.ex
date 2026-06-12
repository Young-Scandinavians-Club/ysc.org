defmodule Ysc.OpenRouter.Mock do
  @moduledoc false

  @doc false
  def do_chat(messages, _config) do
    system_content = content_for_role(messages, "system")
    user_content = content_for_role(messages, "user")

    docs_provided? =
      String.contains?(user_content, "Requested reference documents")

    response =
      cond do
        # Follow-up turn after the mock requested documents below.
        docs_provided? ->
          Jason.encode!(%{
            "answer" =>
              "Answer grounded in loaded docs: #{document_slugs(user_content)}",
            "suggested_step" => nil
          })

        # A question that triggers the on-the-fly document loading path.
        String.contains?(user_content, "deep dive") ->
          Jason.encode!(%{"read_docs" => ["posts", "does-not-exist"]})

        # A question that triggers loading live data from the database.
        String.contains?(user_content, "real examples") ->
          Jason.encode!(%{"read_docs" => ["live-recent-posts"]})

        # Locate stage of the guide finder: pinpoint step + verbatim quote.
        String.contains?(system_content, "pinpoint where in a how-to guide") ->
          Jason.encode!(%{
            "step" => 2,
            "highlight" =>
              "A real copy of the email goes to **your own address**"
          })

        String.contains?(system_content, "guide_slug") ->
          Jason.encode!(%{
            "guide_slug" => "newsletters/send",
            "explanation" => "Use the send guide to deliver your newsletter.",
            "confidence" => "high"
          })

        String.contains?(system_content, "suggested_step") ->
          Jason.encode!(%{
            "answer" =>
              "Add a featured image in Post Settings before publishing.",
            "suggested_step" => 3
          })

        true ->
          Jason.encode!(%{
            "answer" => "See the steps above.",
            "suggested_step" => nil
          })
      end

    {:ok, response}
  end

  defp content_for_role(messages, role) do
    messages
    |> Enum.filter(fn m -> m[:role] == role end)
    |> Enum.map_join("\n", fn m -> m[:content] || "" end)
  end

  defp document_slugs(user_content) do
    ~r/<document slug="([a-z0-9-]+)">/
    |> Regex.scan(user_content)
    |> Enum.map_join(", ", fn [_, slug] -> slug end)
  end
end
