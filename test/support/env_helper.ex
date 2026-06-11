defmodule Ysc.Test.EnvHelper do
  @moduledoc """
  Resets process-global `:ysc, :environment` before each test.

  Several async suites temporarily override this application env. Resetting at
  the start of each test prevents leaked values from breaking env-sensitive
  behavior (Stripe stubs, dev verification codes, SES filtering, etc.).
  """

  @doc false
  def reset_environment! do
    Application.put_env(:ysc, :environment, "test")
  end
end
