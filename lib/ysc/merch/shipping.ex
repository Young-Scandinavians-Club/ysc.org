defmodule Ysc.Merch.Shipping do
  @moduledoc """
  Quotes Printful shipping options for an address and a set of cart/order
  lines. Members pay exactly what Printful quotes at payment time, not an
  earlier cart snapshot.
  """
  require Ysc.Logging

  alias Ysc.Merch.ShippingAddress
  alias Ysc.MoneyHelper
  alias Ysc.Printful.Error

  defp printful_client do
    Application.get_env(:ysc, :printful_client, Ysc.Printful.Client)
  end

  @type option :: %{
          id: String.t(),
          name: String.t(),
          rate: Money.t(),
          min_days: integer() | nil,
          max_days: integer() | nil
        }

  @doc """
  Shipping options for `lines` (maps with `:variant` and `:quantity`), cheapest
  first.

    * `{:error, {:rejected, message}}` - Printful rejected the address or items;
      the message is safe to show the member
    * `{:error, :unavailable}` - Printful could not be reached or returned
      nothing usable; try again later
  """
  @spec options(ShippingAddress.t(), [map()]) ::
          {:ok, [option()]} | {:error, {:rejected, String.t()} | :unavailable}
  def options(%ShippingAddress{} = address, lines) when is_list(lines) do
    items = Enum.map(lines, &to_item/1)

    case printful_client().shipping_rates(
           ShippingAddress.to_recipient(address),
           items
         ) do
      {:ok, rates} when is_list(rates) ->
        parse(rates)

      {:ok, _} ->
        {:error, :unavailable}

      {:error, %Error{type: :invalid, message: message}} ->
        {:error, {:rejected, message}}

      {:error, %Error{} = error} ->
        unavailable(error)
    end
  end

  defp to_item(%{variant: variant, quantity: quantity}) do
    %{variant_id: variant.printful_variant_id, quantity: quantity}
  end

  defp parse(rates) do
    options =
      rates
      |> Enum.flat_map(&parse_rate/1)
      |> Enum.sort_by(&{Money.to_decimal(&1.rate), &1.min_days || 999}, fn {a,
                                                                            a_days},
                                                                           {b,
                                                                            b_days} ->
        case Decimal.compare(a, b) do
          :lt -> true
          :gt -> false
          :eq -> a_days <= b_days
        end
      end)

    case options do
      [] -> {:error, :unavailable}
      options -> {:ok, options}
    end
  end

  defp parse_rate(%{"id" => id, "name" => name, "rate" => rate} = raw)
       when is_binary(id) and is_binary(name) do
    with "USD" <- Map.get(raw, "currency", "USD"),
         %Money{} = money <- MoneyHelper.parse_money(rate) do
      [
        %{
          id: id,
          name: clean_name(name),
          rate: money,
          min_days: Map.get(raw, "minDeliveryDays"),
          max_days: Map.get(raw, "maxDeliveryDays")
        }
      ]
    else
      _ -> []
    end
  end

  defp parse_rate(_), do: []

  # Printful names look like "Flat Rate (Estimated delivery: Oct 21\u2060-23) ":
  # an invisible word-joiner, a trailing space, and a date window that we show
  # ourselves (and that would otherwise appear twice).
  defp clean_name(name) do
    name
    |> String.replace("\u2060", "")
    |> String.replace(~r/\s*\(Estimated delivery:[^)]*\)/i, "")
    |> String.trim()
  end

  defp unavailable(%Error{} = error) do
    Ysc.Logging.warning("Printful shipping quote unavailable",
      type: error.type,
      status: error.status,
      message: error.message
    )

    {:error, :unavailable}
  end

  @doc """
  Re-quotes shipping for the current `lines` and returns the option with the
  same Printful method id as `chosen`, priced for those lines.

  Checkout must call this immediately before creating the pending order so a
  cart that changed after the first quote cannot keep a stale `rate`
  (Finding 92).
  """
  @spec requote(ShippingAddress.t(), [map()], option()) ::
          {:ok, option()}
          | {:error,
             :empty_cart
             | :unavailable
             | :method_unavailable
             | {:rejected, String.t()}}
  def requote(_address, [], _chosen), do: {:error, :empty_cart}

  def requote(%ShippingAddress{} = address, lines, %{id: id})
      when is_list(lines) and is_binary(id) do
    case options(address, lines) do
      {:ok, quoted} ->
        case Enum.find(quoted, &(&1.id == id)) do
          nil -> {:error, :method_unavailable}
          option -> {:ok, option}
        end

      error ->
        error
    end
  end

  @doc "Human delivery window, e.g. \"3-5 business days\"."
  def delivery_window(%{min_days: min, max_days: max})
      when is_integer(min) and is_integer(max) do
    if min == max,
      do: "#{min} business days",
      else: "#{min}-#{max} business days"
  end

  def delivery_window(_), do: nil
end
