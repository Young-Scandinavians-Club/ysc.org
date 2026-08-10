defmodule Ysc.Test.FailingSwooshAdapter do
  @moduledoc """
  Swoosh adapter that always fails delivery, for exercising Mailer.deliver
  error-handling paths.

  By default returns `{:error, :smtp_unavailable}`. Tests that need a
  different failure shape (e.g. to exercise other branches of
  `Ysc.Messages`'s failure-level classification) can override it for the
  duration of a test with `Application.put_env(:ysc, __MODULE__, error: ...)`.
  """
  use Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(_email, _config), do: {:error, configured_error()}

  @impl Swoosh.Adapter
  def deliver_many(_emails, _config), do: {:error, configured_error()}

  defp configured_error do
    Application.get_env(:ysc, __MODULE__, [])
    |> Keyword.get(:error, :smtp_unavailable)
  end
end
