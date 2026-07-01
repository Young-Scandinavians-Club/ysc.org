defmodule Ysc.Test.KioskAPIKeyHelper do
  @moduledoc false

  @lock {:ysc_test_kiosk_api_key, :lock}

  @doc false
  def capture_kiosk_api_key!(value) do
    trans(fn ->
      original = Application.get_env(:ysc, :kiosk_api_key)
      Application.put_env(:ysc, :kiosk_api_key, value)
      original
    end)
  end

  @doc false
  def restore_kiosk_api_key!(original) do
    trans(fn -> restore(original) end)
  end

  @doc false
  def with_kiosk_api_key(value, fun) when is_function(fun, 0) do
    trans(fn ->
      original = Application.get_env(:ysc, :kiosk_api_key)

      try do
        Application.put_env(:ysc, :kiosk_api_key, value)
        fun.()
      after
        restore(original)
      end
    end)
  end

  defp restore(nil), do: Application.delete_env(:ysc, :kiosk_api_key)
  defp restore(value), do: Application.put_env(:ysc, :kiosk_api_key, value)

  defp trans(fun), do: :global.trans(@lock, fun, [Node.self()], :infinity)
end
