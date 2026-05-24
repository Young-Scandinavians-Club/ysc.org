defmodule Ysc.AppleWallet.TestPassbookGenerator do
  @moduledoc false

  @doc """
  Returns a minimal fake .pkpass path without invoking OpenSSL signing.

  `pass_name` is ignored; the file is always created under `System.tmp_dir!/0`
  with a unique name (test-only stub, no OpenSSL).
  """
  # sobelow_skip ["Traversal.FileModule"]
  def generate(_pass, _icon_files, _certs, pass_name)
      when is_binary(pass_name) do
    path =
      Path.join(
        System.tmp_dir!(),
        "ysc-test-pass-#{System.unique_integer([:positive])}.pkpass"
      )

    File.write!(path, "PK\x03\x04TEST")
    {:ok, path}
  end
end
