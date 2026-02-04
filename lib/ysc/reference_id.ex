defmodule Ysc.ReferenceGenerator do
  @moduledoc """
  Generates human-readable unique IDs with a checksum.

  Generates reference IDs in the format:
  `[Prefix]-[Date]-[Random String][Checksum]`
  """

  @prefixes ~w(PMT TKT BKG DON EVT ORD RFD)

  @charset Enum.concat(?A..?Z, ?0..?9)
           |> List.delete(?O)
           |> List.delete(?I)
           |> List.delete(?1)
           |> List.delete(?0)

  @doc """
  Validates a reference ID string.
  Returns :ok if valid, {:error, reason} if invalid.
  """
  @spec validate_reference_id(String.t()) :: :ok | {:error, String.t()}
  def validate_reference_id(reference_id) when is_binary(reference_id) do
    case Regex.run(
           ~r/^([A-Z]{3})-(\d{6})-([A-Z0-9]{4})([A-Z0-9])$/,
           reference_id
         ) do
      [_, prefix, date, random_part, checksum] ->
        with :ok <- validate_format(prefix, date, random_part, checksum) do
          validate_checksum(prefix, date, random_part, checksum)
        end

      nil ->
        {:error, "Invalid format"}
    end
  end

  @spec validate_format(String.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, String.t()}
  defp validate_format(prefix, date, random_part, checksum) do
    cond do
      prefix not in @prefixes ->
        {:error, "Invalid prefix"}

      String.length(date) != 6 or not Regex.match?(~r/^\d{6}$/, date) ->
        {:error, "Invalid date format"}

      not valid_base36_string?(random_part) ->
        {:error, "Invalid random part"}

      String.length(checksum) != 1 ->
        {:error, "Invalid checksum character"}

      true ->
        :ok
    end
  end

  @spec validate_checksum(String.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, String.t()}
  defp validate_checksum(prefix, date, random_part, checksum) do
    base = "#{prefix}#{date}#{random_part}"
    expected_checksum = compute_checksum(base)

    if checksum == expected_checksum do
      :ok
    else
      {:error, "Checksum validation failed"}
    end
  end

  @spec valid_base36_string?(String.t()) :: boolean()
  defp valid_base36_string?(string) do
    String.upcase(string)
    |> String.to_charlist()
    |> Enum.all?(&(&1 in @charset))
  end

  @doc """
  Generates a new reference ID with the given prefix.
  """
  @spec generate_reference_id(String.t()) :: String.t()
  def generate_reference_id(prefix) when is_binary(prefix) do
    if valid_prefix?(prefix) do
      date_part = current_date_part()
      random_part = generate_random_part(4)
      base = "#{prefix}#{date_part}#{random_part}"
      checksum = compute_checksum(base)

      "#{prefix}-#{date_part}-#{random_part}#{checksum}"
    else
      raise ArgumentError, "Invalid prefix: #{prefix}"
    end
  end

  @spec valid_prefix?(String.t()) :: boolean()
  defp valid_prefix?(prefix) do
    prefix in @prefixes
  end

  @spec current_date_part() :: String.t()
  defp current_date_part do
    Date.utc_today()
    |> Date.to_string()
    |> String.replace("-", "")
    |> String.slice(2, 6)
  end

  @spec generate_random_part(non_neg_integer()) :: String.t()
  defp generate_random_part(length) do
    for _ <- 1..length, into: "" do
      <<Enum.random(@charset)>>
    end
  end

  @doc """
  Computes the checksum for a reference ID base string.
  """
  @spec compute_checksum(String.t()) :: String.t()
  def compute_checksum(base) do
    base
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, acc -> acc + char end)
    |> rem(36)
    |> to_base36()
  end

  @spec to_base36(non_neg_integer()) :: String.t()
  defp to_base36(value) when value < 10, do: Integer.to_string(value)
  defp to_base36(value), do: <<value - 10 + ?A>>
end
