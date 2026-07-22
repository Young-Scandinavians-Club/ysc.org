defmodule YscWeb.ReauthResume do
  @moduledoc """
  Signed resume tokens for sensitive settings flows that require re-authentication.

  OAuth reauth leaves the LiveView process, so pending email/phone/password intents
  must travel in the `return_to` URL as a signed token and be restored on return.
  """

  @salt "reauth resume intent"
  @max_age 600

  @doc """
  Signs a reauth intent map for embedding in an OAuth `return_to` URL.
  """
  def sign(intent) when is_map(intent) do
    Phoenix.Token.sign(YscWeb.Endpoint, @salt, intent, max_age: @max_age)
  end

  @doc """
  Verifies a resume token. Returns `{:ok, intent}` or `:error`.
  """
  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(YscWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, intent} when is_map(intent) -> {:ok, intent}
      _ -> :error
    end
  end

  def verify(_), do: :error

  @doc """
  Appends a signed `reauth_resume` query param to an internal path.
  """
  def append_to_path(path, intent) when is_binary(path) and is_map(intent) do
    token = sign(intent)
    uri = URI.parse(path)
    query = URI.decode_query(uri.query || "")
    query = Map.put(query, "reauth_resume", token)

    uri
    |> Map.put(:query, URI.encode_query(query))
    |> URI.to_string()
  end
end
