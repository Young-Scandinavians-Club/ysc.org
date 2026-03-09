defmodule Ysc.WpMigration.PhpDeserialize do
  @moduledoc """
  Parses PHP serialized strings into Elixir data structures.

  Supports the subset used by Ultimate Member / WooCommerce:
    N;          → nil
    b:0;        → false  /  b:1; → true
    i:N;        → integer
    d:N;        → float
    s:LEN:VAL;  → binary string (binary-length-safe, handles embedded ;)
    a:N:{...}   → map with string keys (integer keys are stringified)
  """

  @doc """
  Parses a PHP-serialized binary. Returns the decoded Elixir value, or `nil`
  if the input is nil/empty/unparseable.
  """
  def parse(nil), do: nil
  def parse(""), do: nil

  def parse(data) when is_binary(data) do
    try do
      {value, _rest} = do_parse(data)
      value
    rescue
      _ -> nil
    end
  end

  @doc """
  Like `parse/1` but always returns a map; returns `%{}` if unparseable.
  Useful when you know the value is a PHP associative array.
  """
  def parse_map(data) do
    case parse(data) do
      map when is_map(map) -> map
      _ -> %{}
    end
  end

  # -------------------------------------------------------------------------
  # Core recursive parser — returns {value, remaining_binary}
  # -------------------------------------------------------------------------

  defp do_parse(<<"N;", rest::binary>>), do: {nil, rest}
  defp do_parse(<<"b:0;", rest::binary>>), do: {false, rest}
  defp do_parse(<<"b:1;", rest::binary>>), do: {true, rest}

  defp do_parse(<<"i:", rest::binary>>) do
    {digits, tail} = take_until(rest, ?;)
    {String.to_integer(digits), tail}
  end

  defp do_parse(<<"d:", rest::binary>>) do
    {digits, tail} = take_until(rest, ?;)
    {parse_float(digits), tail}
  end

  defp do_parse(<<"s:", rest::binary>>) do
    {len_str, after_colon} = take_until(rest, ?:)
    len = String.to_integer(len_str)
    # Read exactly `len` bytes then expect ;
    <<value::binary-size(len), ";", tail::binary>> = after_colon
    {value, tail}
  end

  defp do_parse(<<"a:", rest::binary>>) do
    {count_str, after_colon} = take_until(rest, ?:)
    count = String.to_integer(count_str)
    <<"{", tail::binary>> = after_colon
    {pairs, tail2} = parse_pairs(tail, count, [])
    map = Map.new(pairs, fn {k, v} -> {to_string(k), v} end)
    {map, tail2}
  end

  # Object support (O:) — treat the same as associative array for our purposes
  defp do_parse(<<"O:", rest::binary>>) do
    # Skip class name, then parse like an array
    {_class_len_str, after_first_colon} = take_until(rest, ?:)
    {_class_name, after_class} = take_until(after_first_colon, ?:)
    {count_str, after_colon} = take_until(after_class, ?:)
    count = String.to_integer(count_str)
    <<"{", tail::binary>> = after_colon
    {pairs, tail2} = parse_pairs(tail, count, [])
    map = Map.new(pairs, fn {k, v} -> {to_string(k), v} end)
    {map, tail2}
  end

  defp parse_pairs(<<"}", tail::binary>>, 0, acc), do: {Enum.reverse(acc), tail}

  defp parse_pairs(rest, n, acc) do
    {key, rest2} = do_parse(rest)
    {val, rest3} = do_parse(rest2)
    parse_pairs(rest3, n - 1, [{key, val} | acc])
  end

  # Consume bytes until `char` (exclusive), return {consumed, rest_after_char}
  defp take_until(bin, char), do: take_until(bin, char, [])

  defp take_until(<<c, rest::binary>>, char, acc) when c == char,
    do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}

  defp take_until(<<c, rest::binary>>, char, acc),
    do: take_until(rest, char, [c | acc])

  defp parse_float(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end
end
