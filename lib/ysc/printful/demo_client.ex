defmodule Ysc.Printful.DemoClient do
  @moduledoc """
  A stand-in for Printful that needs no account, token or network, so the whole
  merch flow (catalog sync, shipping quotes, checkout, order submission) can be
  exercised locally.

  It is selected automatically in dev when `PRINTFUL_API_TOKEN` is unset (see
  `config/runtime.exs`). Set a token to use the real client against a Printful
  test store instead.

  Orders are kept in memory (an `Agent`), so they disappear when the server
  restarts. Prices, costs and shipping rates are made up but shaped like
  Printful's.
  """
  @behaviour Ysc.Printful.ClientBehaviour

  alias Ysc.Printful.Error

  @store __MODULE__.Store

  # {product id, name, static image, base cost, retail price, colors, sizes}
  @catalog [
    {9001, "Viking Tee", "/images/viking_on_bike.png", "13.50", "28.00",
     ["Black", "White"], ["S", "M", "L", "XL", "2XL"]},
    {9002, "Club Hoodie", "/images/ysc_75th.jpg", "29.00", "52.00",
     ["Navy", "Heather Grey"], ["S", "M", "L", "XL"]},
    {9003, "Tomte Sticker", "/images/lost_tomte.webp", "1.80", "4.00", [], []},
    {9004, "Camp Mug", "/images/scandi_countries.jpg", "8.50", "16.00",
     ["White", "Black"], []}
  ]

  # Mockup photos per product and color (nil = the product has no colors), in
  # the order they should appear. Demo only: stand-ins from the app's own assets.
  @photos %{
    9001 => %{
      "Black" => ["/images/viking_on_bike.png", "/images/flags.jpg"],
      "White" => ["/images/ysc_75th.jpg"]
    },
    9002 => %{
      "Navy" => ["/images/ysc_75th.jpg", "/images/ysc_bonfire_2024.jpg"],
      "Heather Grey" => ["/images/tahoe-cabin-feature.jpg"]
    },
    9003 => %{nil => ["/images/lost_tomte.webp", "/images/flags.jpg"]},
    9004 => %{
      "White" => ["/images/scandi_countries.jpg"],
      "Black" => ["/images/flags.jpg", "/images/scandi_countries.jpg"]
    }
  }

  ## Catalog

  @impl true
  def list_sync_products do
    {:ok,
     for {id, name, image, _cost, _price, _colors, _sizes} = product <- @catalog do
       %{
         "id" => id,
         "external_id" => "demo-#{id}",
         "name" => name,
         "thumbnail_url" => image_url(image),
         "variants" => length(variants(product)),
         "synced" => length(variants(product)),
         "is_ignored" => false
       }
     end}
  end

  @impl true
  def get_sync_product(printful_product_id) do
    case Enum.find(@catalog, fn {id, _, _, _, _, _, _} ->
           id == printful_product_id
         end) do
      nil ->
        {:error,
         %Error{
           type: :not_found,
           status: 404,
           message: "Demo product not found"
         }}

      {id, name, image, _cost, _price, _colors, _sizes} = product ->
        {:ok,
         %{
           "sync_product" => %{
             "id" => id,
             "name" => name,
             "thumbnail_url" => image_url(image),
             "is_ignored" => false
           },
           "sync_variants" => variants(product)
         }}
    end
  end

  defp variants({product_id, name, image, _cost, price, colors, sizes}) do
    colors = if colors == [], do: [nil], else: colors
    sizes = if sizes == [], do: [nil], else: sizes

    for {color, ci} <- Enum.with_index(colors),
        {size, si} <- Enum.with_index(sizes) do
      sync_id = product_id * 100 + ci * 10 + si

      %{
        "id" => sync_id,
        "variant_id" => catalog_variant_id(sync_id),
        "name" =>
          [name, color, size] |> Enum.reject(&is_nil/1) |> Enum.join(" / "),
        "color" => color,
        "size" => size,
        "sku" => "DEMO-#{sync_id}",
        "retail_price" => price,
        "availability_status" => "active",
        "is_ignored" => false,
        "files" =>
          for path <- photos_for(product_id, color, image) do
            %{"type" => "preview", "preview_url" => image_url(path)}
          end
      }
    end
  end

  defp photos_for(product_id, color, default) do
    @photos |> Map.get(product_id, %{}) |> Map.get(color, [default])
  end

  defp catalog_variant_id(sync_id), do: sync_id + 9_000_000

  # The server-side fetch guard always refuses the hostname "localhost" but
  # allows loopback IPs in dev, so point at 127.0.0.1.
  defp image_url(path) do
    uri = URI.parse(YscWeb.Endpoint.url())
    host = if uri.host == "localhost", do: "127.0.0.1", else: uri.host
    URI.to_string(%{uri | host: host, path: path})
  end

  # cost basis per catalog variant id, for estimates
  defp unit_cost_by_catalog_id(catalog_id) do
    sync_id = catalog_id - 9_000_000
    product_id = div(sync_id, 100)

    case Enum.find(@catalog, fn {id, _, _, _, _, _, _} -> id == product_id end) do
      {_, _, _, cost, _, _, _} -> Decimal.new(cost)
      nil -> Decimal.new("10.00")
    end
  end

  defp unit_cost_by_sync_id(sync_id),
    do: unit_cost_by_catalog_id(catalog_variant_id(sync_id))

  ## Shipping and costs

  # The demo store has no Printful catalog behind it; the shop then falls back
  # to naming the color.
  @impl true
  def get_catalog_product(_catalog_product_id) do
    {:error, %Ysc.Printful.Error{type: :not_found, message: "Not Found"}}
  end

  @impl true
  def shipping_rates(recipient, items) do
    cond do
      Map.get(recipient, :country_code, "US") != "US" ->
        {:error,
         %Error{
           type: :invalid,
           status: 400,
           message: "Demo shop only ships to the US"
         }}

      Map.get(recipient, :zip) == "00000" ->
        {:error,
         %Error{
           type: :invalid,
           status: 400,
           message: "Zip code does not match state"
         }}

      true ->
        quantity = items |> Enum.map(& &1.quantity) |> Enum.sum()
        extra = max(quantity - 1, 0)

        {:ok,
         [
           rate(
             "STANDARD",
             "Flat Rate (3-5 business days)",
             "4.99",
             "1.99",
             extra,
             3,
             5
           ),
           rate(
             "EXPRESS",
             "Express (1-2 business days)",
             "14.99",
             "3.00",
             extra,
             1,
             2
           )
         ]}
    end
  end

  defp rate(id, name, first, additional, extra, min, max) do
    total =
      Decimal.add(
        Decimal.new(first),
        Decimal.mult(Decimal.new(additional), extra)
      )

    %{
      "id" => id,
      "name" => name,
      "rate" => Decimal.to_string(total),
      "currency" => "USD",
      "minDeliveryDays" => min,
      "maxDeliveryDays" => max,
      # Like Printful: dates include a couple of days to make the item.
      "minDeliveryDate" => demo_delivery_date(min),
      "maxDeliveryDate" => demo_delivery_date(max)
    }
  end

  defp demo_delivery_date(days),
    do: Date.utc_today() |> Date.add(days + 2) |> Date.to_iso8601()

  @impl true
  def estimate_costs(order) do
    {:ok, %{"costs" => costs(order)}}
  end

  defp costs(order) do
    items =
      order
      |> Map.get(:items, [])
      |> Enum.reduce(Decimal.new(0), fn item, acc ->
        unit = unit_cost_by_sync_id(Map.get(item, :sync_variant_id, 0))
        Decimal.add(acc, Decimal.mult(unit, Map.get(item, :quantity, 1)))
      end)

    quantity =
      order |> Map.get(:items, []) |> Enum.map(& &1.quantity) |> Enum.sum()

    shipping =
      Decimal.add(
        Decimal.new("4.99"),
        Decimal.mult(Decimal.new("1.99"), max(quantity - 1, 0))
      )

    %{
      "currency" => "USD",
      "subtotal" => Decimal.to_string(items),
      "shipping" => Decimal.to_string(shipping),
      "tax" => "0.00",
      "total" => items |> Decimal.add(shipping) |> Decimal.to_string()
    }
  end

  ## Orders

  @impl true
  def create_order(order, confirm) when is_boolean(confirm) do
    external_id = Map.get(order, :external_id)

    case find_by_external_id(external_id) do
      %{} = existing ->
        {:ok, existing}

      nil ->
        id = System.unique_integer([:positive, :monotonic]) + 100_000

        record = %{
          "id" => id,
          "external_id" => external_id,
          "status" => if(confirm, do: "pending", else: "draft"),
          "shipping" => Map.get(order, :shipping),
          "recipient" => stringify(Map.get(order, :recipient, %{})),
          # Like Printful, each item gets an id of its own; shipments refer to it.
          "items" =>
            order
            |> Map.get(:items, [])
            |> Enum.with_index(1)
            |> Enum.map(fn {item, index} ->
              item |> stringify() |> Map.put("id", id * 100 + index)
            end),
          "costs" => costs(order),
          "shipments" => []
        }

        put_order(record)
        {:ok, record}
    end
  end

  @impl true
  def get_order_by_external_id(external_id) do
    case find_by_external_id(external_id) do
      nil ->
        {:error,
         %Error{type: :not_found, status: 404, message: "Order not found"}}

      order ->
        {:ok, order}
    end
  end

  @impl true
  def get_order(id) do
    case Map.get(all_orders(), to_int(id)) do
      nil ->
        {:error,
         %Error{type: :not_found, status: 404, message: "Order not found"}}

      order ->
        {:ok, order}
    end
  end

  @impl true
  def confirm_order(id) do
    update_existing(id, fn order ->
      if order["status"] == "draft",
        do: Map.put(order, "status", "pending"),
        else: order
    end)
  end

  @impl true
  def cancel_order(id) do
    update_existing(id, &Map.put(&1, "status", "canceled"))
  end

  @doc "Every order the demo has received, newest first. For the dev tools."
  def list_orders do
    all_orders() |> Map.values() |> Enum.sort_by(& &1["id"], :desc)
  end

  @doc "Applies `fun` to a demo order (dev tools: move it through production)."
  def update_order(id, fun) when is_function(fun, 1),
    do: update_existing(id, fun)

  ## Webhooks (accepted and ignored: the demo has nothing to call back)

  @impl true
  def set_webhooks(url, types), do: {:ok, %{"url" => url, "types" => types}}

  @impl true
  def get_webhooks, do: {:ok, %{"url" => nil, "types" => []}}

  ## Storage

  defp all_orders do
    Agent.get(store(), & &1)
  end

  defp find_by_external_id(nil), do: nil

  defp find_by_external_id(external_id) do
    all_orders()
    |> Map.values()
    |> Enum.find(&(&1["external_id"] == external_id))
  end

  defp put_order(record) do
    Agent.update(store(), &Map.put(&1, record["id"], record))
  end

  defp update_existing(id, fun) do
    id = to_int(id)

    Agent.get_and_update(store(), fn orders ->
      case Map.fetch(orders, id) do
        {:ok, order} ->
          updated = fun.(order)
          {{:ok, updated}, Map.put(orders, id, updated)}

        :error ->
          {{:error,
            %Error{type: :not_found, status: 404, message: "Order not found"}},
           orders}
      end
    end)
  end

  # Started on first use rather than under the supervision tree: the demo only
  # exists in dev and must never affect a real boot.
  defp store do
    case Process.whereis(@store) do
      nil ->
        case Agent.start(fn -> %{} end, name: @store) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end

      pid ->
        pid
    end
  end

  defp to_int(id) when is_integer(id), do: id
  defp to_int(id) when is_binary(id), do: String.to_integer(id)

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
