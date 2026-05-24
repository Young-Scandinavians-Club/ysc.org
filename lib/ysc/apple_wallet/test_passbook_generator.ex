defmodule Ysc.AppleWallet.TestPassbookGenerator do
  @moduledoc false

  @doc """
  Returns a minimal fake .pkpass path without invoking OpenSSL signing.
  """
  def generate(_pass, _icon_files, _certs, pass_name)
      when is_binary(pass_name) do
    path =
      System.tmp_dir!()
      |> Path.join(
        "test-#{pass_name}-#{System.unique_integer([:positive])}.pkpass"
      )

    File.write!(path, "PK\x03\x04TEST")
    {:ok, path}
  end
end
