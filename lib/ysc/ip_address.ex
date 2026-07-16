defmodule Ysc.IpAddress do
  @moduledoc """
  Helpers for normalizing and masking IP addresses in member-facing copy.
  """

  @doc """
  Normalizes an IP string for lookups and comparisons.

  Trims whitespace, parses via `:inet`, and returns canonical IPv4 or IPv6 text.
  Unparseable input is returned unchanged.
  """
  def normalize(ip) when is_binary(ip) do
    ip
    |> String.trim()
    |> case do
      "" ->
        nil

      trimmed ->
        case :inet.parse_address(String.to_charlist(trimmed)) do
          {:ok, {a, b, c, d}} ->
            "#{a}.#{b}.#{c}.#{d}"

          {:ok, {0, 0, 0, 0, 0, 65_535, hi, lo}} ->
            <<a, b, c, d>> = <<hi::16, lo::16>>
            "#{a}.#{b}.#{c}.#{d}"

          {:ok, parsed} ->
            parsed |> :inet.ntoa() |> to_string()

          {:error, _} ->
            trimmed
        end
    end
  end

  def normalize(_), do: nil

  @doc """
  Masks an IP for display in security-related UI and emails.

  IPv4 addresses keep the first two octets; IPv6 keeps the first two groups.
  Returns `nil` when the value is blank or cannot be masked.
  """
  def mask(nil), do: nil
  def mask(""), do: nil

  def mask(ip) when is_binary(ip) do
    case normalize(ip) do
      nil ->
        nil

      normalized ->
        mask_normalized(normalized)
    end
  end

  def mask(_), do: nil

  defp mask_normalized(ip) do
    case String.split(ip, ".") do
      [a, b, _, _] ->
        "#{a}.#{b}.xxx.xxx"

      _ ->
        case String.split(ip, ":") do
          [a, b, _ | _] ->
            "#{a}:#{b}:xxxx:..."

          _ ->
            nil
        end
    end
  end
end
