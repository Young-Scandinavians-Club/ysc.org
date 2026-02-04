defmodule YscWeb.Plugs.CSPNonce do
  @moduledoc """
  Generates a Content Security Policy (CSP) nonce for each request.
  This allows inline scripts and styles to be executed securely without
  using 'unsafe-inline', which is a security risk.

  The nonce is stored in conn.assigns[:csp_nonce] and will be used by
  the SecurityHeaders plug to build the CSP policy.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # Generate a random 16-byte base64 string
    nonce = :crypto.strong_rand_bytes(16) |> Base.encode64()

    # Store nonce in assigns for use in templates and SecurityHeaders plug
    assign(conn, :csp_nonce, nonce)
  end
end
