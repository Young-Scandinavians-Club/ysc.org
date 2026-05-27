defmodule YscWeb.AccountSetupAccess do
  @moduledoc """
  Gates unauthenticated account-setup email verification behind a signed token.

  The public `/account/setup/:user_id` route must stay reachable without login so new
  members can verify email, but sending codes and submitting guesses must not be
  available to anyone who only knows (or guesses) a user id.
  """

  use YscWeb, :verified_routes

  @salt "account_setup_access"
  @max_age 60 * 60 * 24 * 14

  @doc """
  Signs a short-lived token that authorizes email verification for `user_id`.
  """
  def sign(user_id) when is_binary(user_id) do
    Phoenix.Token.sign(YscWeb.Endpoint, @salt, user_id, max_age: @max_age)
  end

  @doc false
  def verify(token, user_id)
      when is_binary(token) and byte_size(token) > 0 and is_binary(user_id) do
    case Phoenix.Token.verify(YscWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, ^user_id} -> true
      _ -> false
    end
  end

  def verify(_, _), do: false

  @doc """
  Builds the account setup path with a `setup_token` query param.

  Extra string-keyed params (e.g. `"from_signup" => "true"`) are appended for UX only;
  they are not a security control.
  """
  def setup_path(user_id, extra_params \\ %{}) when is_binary(user_id) do
    params =
      extra_params
      |> Map.new(fn {k, v} -> {to_string(k), to_string(v)} end)
      |> Map.put("setup_token", sign(user_id))

    ~p"/account/setup/#{user_id}?#{params}"
  end

  @doc """
  Returns true when the visitor may send or check email verification codes for `user_id`.
  """
  def email_verification_authorized?(
        user_id,
        current_user,
        setup_access_granted
      )
      when is_binary(user_id) do
    owner?(user_id, current_user) or setup_access_granted == true
  end

  defp owner?(user_id, %{id: user_id}), do: true
  defp owner?(_, _), do: false

  def on_mount(:default, %{"user_id" => user_id} = params, _session, socket) do
    granted? = verify(params["setup_token"], user_id)

    {:cont, Phoenix.Component.assign(socket, :setup_access_granted, granted?)}
  end

  def on_mount(:default, _params, _session, socket) do
    {:cont, Phoenix.Component.assign(socket, :setup_access_granted, false)}
  end
end
