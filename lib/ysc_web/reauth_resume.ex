defmodule YscWeb.ReauthResume do
  @moduledoc """
  Encrypted resume tokens for sensitive settings flows that require re-authentication.

  OAuth reauth leaves the LiveView process, so pending email/phone/password intents
  must travel in the `return_to` URL as an encrypted token and be restored on return.

  Tokens are bound to the user who started the reauth flow (`user_id` in the payload).
  Without that binding, a resume token minted for user A could be opened by user B
  during B's post-login / OAuth reauth grace window and apply A's pending email/phone
  change (or profile params) to B's account.
  """

  @salt "reauth resume intent"
  @max_age 600

  @doc """
  Encrypts a reauth intent map for embedding in an OAuth `return_to` URL.

  `intent` must include a binary `"user_id"` matching the account that started
  the sensitive flow.
  """
  def sign(%{"user_id" => user_id} = intent)
      when is_binary(user_id) and user_id != "" do
    Phoenix.Token.encrypt(YscWeb.Endpoint, @salt, intent, max_age: @max_age)
  end

  def sign(_intent) do
    raise ArgumentError,
          "ReauthResume.sign/1 requires a non-empty binary \"user_id\" in the intent"
  end

  @doc """
  Decrypts and verifies a resume token for `user_id`.

  Returns `{:ok, intent}` only when the token is valid, unexpired, and bound to
  `user_id`. Otherwise `:error`.
  """
  def verify(token, user_id)
      when is_binary(token) and is_binary(user_id) and user_id != "" do
    case Phoenix.Token.decrypt(YscWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, %{"user_id" => bound_id} = intent}
      when is_binary(bound_id) and bound_id != "" ->
        if byte_size(bound_id) == byte_size(user_id) and
             Plug.Crypto.secure_compare(bound_id, user_id) do
          {:ok, intent}
        else
          :error
        end

      _ ->
        :error
    end
  end

  def verify(_, _), do: :error

  @doc """
  Appends an encrypted `reauth_resume` query param to an internal path.

  `intent` must include `"user_id"` (see `sign/1`).
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
