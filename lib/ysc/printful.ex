defmodule Ysc.Printful do
  @moduledoc """
  Helpers about which Printful backend is active.
  """

  @doc """
  True when the merch shop is running against the built-in fake Printful
  (dev without a `PRINTFUL_API_TOKEN`). Orders placed in this mode never reach
  a real printer.
  """
  @spec demo_mode?() :: boolean()
  def demo_mode? do
    Application.get_env(:ysc, :printful_client) == Ysc.Printful.DemoClient
  end
end
