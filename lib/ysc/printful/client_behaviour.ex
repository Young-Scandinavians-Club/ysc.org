defmodule Ysc.Printful.ClientBehaviour do
  @moduledoc """
  Behaviour for the Printful API client, so tests can swap in a stub via
  `config :ysc, :printful_client`.

  Success values are the decoded `"result"` payload from Printful (string
  keys). Failures are `Ysc.Printful.Error` structs.
  """

  alias Ysc.Printful.Error

  @type result(t) :: {:ok, t} | {:error, Error.t()}

  @doc "Lists every sync product in the store (all pages)."
  @callback list_sync_products() :: result([map()])

  @doc """
  Fetches one sync product. Returns `%{"sync_product" => map, "sync_variants" => [map]}`.
  """
  @callback get_sync_product(printful_product_id :: integer()) :: result(map())

  @doc """
  Quotes shipping options. `items` are `%{variant_id: catalog_id, quantity: n}`.
  """
  @callback shipping_rates(recipient :: map(), items :: [map()]) ::
              result([map()])

  @doc """
  Estimates what Printful will charge for an order (items, shipping, tax).
  """
  @callback estimate_costs(order :: map()) :: result(map())

  @doc """
  Creates an order. With `confirm: true` Printful accepts it for fulfillment
  and bills the store's payment method; otherwise it stays a draft.
  """
  @callback create_order(order :: map(), confirm :: boolean()) :: result(map())

  @doc "Looks an order up by our `external_id`. `{:error, %{type: :not_found}}` if absent."
  @callback get_order_by_external_id(external_id :: String.t()) ::
              result(map())

  @callback get_order(printful_order_id :: integer() | String.t()) ::
              result(map())

  @callback confirm_order(printful_order_id :: integer() | String.t()) ::
              result(map())

  @callback cancel_order(printful_order_id :: integer() | String.t()) ::
              result(map())

  @doc "Registers (or replaces) the store's webhook configuration."
  @callback set_webhooks(url :: String.t(), types :: [String.t()]) ::
              result(map())

  @callback get_webhooks() :: result(map())
end
