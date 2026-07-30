defmodule QueryConsole.Runner.Cells do
  @moduledoc false

  @doc """
  Convert a Postgrex cell value into something Jason can encode for LiveView/JS.

  UUID/ULID columns are normally already Crockford strings via
  `QueryConsole.Postgrex.ULID`; this still decodes any leftover 16-byte binaries.
  """
  def serialize(nil), do: nil
  def serialize(%Date{} = d), do: Date.to_iso8601(d)
  def serialize(%Time{} = t), do: Time.to_iso8601(t)
  def serialize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def serialize(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  def serialize(%Decimal{} = d), do: Decimal.to_string(d)
  def serialize(v) when is_boolean(v) or is_integer(v) or is_float(v), do: v

  def serialize(list) when is_list(list), do: Enum.map(list, &serialize/1)

  def serialize(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), serialize(v)} end)
  end

  def serialize(<<_::128>> = bin) do
    case decode_ulid(bin) do
      {:ok, ulid} -> ulid
      :error -> hex_binary(bin)
    end
  end

  def serialize(bin) when is_binary(bin) do
    if String.valid?(bin) do
      bin
    else
      hex_binary(bin)
    end
  end

  def serialize(other), do: inspect(other)

  defp decode_ulid(<<_::128>> = bin) do
    # Ecto.ULID.load/1 returns {:ok, string} | :error (via encode/1).
    Ecto.ULID.load(bin)
  end

  defp hex_binary(bin), do: "\\x" <> Base.encode16(bin, case: :lower)
end
