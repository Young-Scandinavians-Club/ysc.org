defmodule Ysc.AppleWallet.CapturingPassbookGenerator do
  @moduledoc false

  # Test-only Passbook.generate/4 stand-in that records the pass struct so
  # tests can assert barcode identity, then delegates to the zip stub.
  def generate(pass, icon_files, certs, pass_name) do
    pid = Application.get_env(:ysc, :apple_wallet_pass_capture_pid, self())
    send(pid, {:apple_wallet_pass, pass})

    Ysc.AppleWallet.TestPassbookGenerator.generate(
      pass,
      icon_files,
      certs,
      pass_name
    )
  end
end
