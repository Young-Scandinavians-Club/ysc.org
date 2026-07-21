defmodule Ysc.OpenRouter do
  @moduledoc """
  Minimal OpenRouter chat completions client (OpenAI-compatible API).

  Used for grounded admin help assistant features. Configure via `config :ysc, :open_router`.
  """

  require Ysc.Logging

  @default_api "https://openrouter.ai/api/v1/chat/completions"
  @default_model "deepseek/deepseek-v4-flash"

  @doc """
  Sends a chat completion request.

  `messages` is a list of `%{role: "system" | "user" | "assistant", content: String.t()}`.

  Returns `{:ok, content_string}` or `{:error, reason}`.
  """
  def chat(messages, opts \\ []) when is_list(messages) do
    config = config()

    if blank?(config[:api_key]) do
      {:error, :not_configured}
    else
      client = Application.get_env(:ysc, :open_router_client, __MODULE__)
      client.do_chat(messages, Keyword.merge(config, opts))
    end
  end

  @doc false
  def do_chat(messages, config) do
    api = config[:api] || @default_api
    model = config[:model] || @default_model
    referer = config[:referer] || default_referer()

    body = %{
      model: model,
      messages: messages,
      temperature: 0.2
    }

    headers = [
      {"authorization", "Bearer #{config[:api_key]}"},
      {"content-type", "application/json"},
      {"http-referer", referer},
      {"x-title", "YSC Admin Help"}
    ]

    case Req.post(api,
           json: body,
           headers: headers,
           receive_timeout: 60_000
         ) do
      {:ok,
       %{
         status: 200,
         body: %{"choices" => [%{"message" => %{"content" => content}} | _]}
       }}
      when is_binary(content) ->
        {:ok, String.trim(content)}

      {:ok, %{status: 200, body: body}} ->
        Ysc.Logging.warning(
          "OpenRouter unexpected response shape (model=#{model}): " <>
            response_summary(body),
          extra: %{model: model, response_bytes: response_byte_size(body)}
        )

        {:error, :invalid_response}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 402}} ->
        {:error, :payment_required}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Ysc.Logging.warning(
          "OpenRouter HTTP error (status=#{status} model=#{model}): " <>
            response_summary(body),
          extra: %{
            status: status,
            model: model,
            response_bytes: response_byte_size(body)
          }
        )

        {:error, {:http_error, status}}

      {:error, reason} ->
        Ysc.Logging.warning(
          "OpenRouter request failed (model=#{model}): #{inspect(reason)}",
          extra: %{reason: inspect(reason), model: model}
        )

        {:error, :request_failed}
    end
  end

  defp response_summary(body) do
    inspect(body, limit: 100, printable_limit: 100)
  end

  defp response_byte_size(body) when is_binary(body), do: byte_size(body)

  defp response_byte_size(body) do
    body
    |> inspect(limit: 100, printable_limit: 100)
    |> byte_size()
  end

  defp config do
    Application.get_env(:ysc, :open_router, [])
  end

  defp default_referer do
    case Application.get_env(:ysc, :github_repo_slug) do
      slug when is_binary(slug) and slug != "" -> "https://github.com/#{slug}"
      _ -> "https://ysc.org"
    end
  end

  defp blank?(nil), do: true
  defp blank?(str) when is_binary(str), do: String.trim(str) == ""
  defp blank?(_), do: true
end
