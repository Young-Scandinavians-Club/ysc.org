defmodule Ysc.AutoLoginOneTime do
  @moduledoc false
  use Hammer, backend: :ets

  # Slightly longer than `UserSessionController` @auto_login_token_max_age (Phoenix.Token.verify)
  @window_ms 130_000

  @doc """
  Rejects a replay of the same raw auto-login token while it remains valid. First
  `consume_once/1` in the window returns `:ok`; a second use returns
  `{:error, :already_used}`.
  """
  @spec consume_once(String.t()) :: :ok | {:error, :already_used}
  def consume_once(token) when is_binary(token) do
    id = :crypto.hash(:sha256, token) |> Base.url_encode64(padding: false)
    key = "autologin_onetime:" <> id

    case hit(key, @window_ms, 1) do
      {:allow, _} -> :ok
      {:deny, _} -> {:error, :already_used}
    end
  end
end
