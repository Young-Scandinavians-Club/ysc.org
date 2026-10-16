defmodule Ysc.Printful.Client do
  @moduledoc """
  Printful API client (v1; sync products are not yet available in v2).

  ## Configuration

  Set at runtime in `config/runtime.exs` from the environment:

    * `PRINTFUL_API_TOKEN` - private token (required)
    * `PRINTFUL_STORE_ID` - sent as `X-PF-Store-Id`; required for account-level
      tokens, harmless for store-level tokens
    * `PRINTFUL_WEBHOOK_SECRET` - used by the webhook controller, not here

  Without a token every call returns `{:error, %Ysc.Printful.Error{type: :not_configured}}`
  so a dev machine without credentials never reaches the network.

  Printful has no sandbox. Point a dev token at a separate Printful test
  store; orders are only billed once confirmed.
  """
  @behaviour Ysc.Printful.ClientBehaviour

  require Ysc.Logging

  alias Ysc.Printful.Error

  @api_base_url "https://api.printful.com"
  @page_size 100
  # Hard stop so a paging bug can never loop forever.
  @max_pages 50

  @impl true
  def list_sync_products do
    list_pages(0, [])
  end

  defp list_pages(_offset, acc) when length(acc) >= @page_size * @max_pages do
    {:ok, acc}
  end

  defp list_pages(offset, acc) do
    case request(:get, "/store/products",
           params: [limit: @page_size, offset: offset]
         ) do
      {:ok, %{"result" => page} = body} when is_list(page) ->
        acc = acc ++ page
        total = get_in(body, ["paging", "total"]) || length(acc)

        if page == [] or length(acc) >= total do
          {:ok, acc}
        else
          list_pages(offset + @page_size, acc)
        end

      {:ok, _unexpected} ->
        {:error, invalid("Unexpected response listing products")}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def get_sync_product(printful_product_id) do
    result(request(:get, "/store/products/#{printful_product_id}"))
  end

  @impl true
  def shipping_rates(recipient, items) do
    body = %{
      recipient: recipient,
      items: items,
      currency: "USD",
      locale: "en_US"
    }

    result(request(:post, "/shipping/rates", json: body))
  end

  @impl true
  def estimate_costs(order) do
    result(request(:post, "/orders/estimate-costs", json: order))
  end

  @impl true
  def create_order(order, confirm) when is_boolean(confirm) do
    params = if confirm, do: [confirm: "true"], else: []
    result(request(:post, "/orders", json: order, params: params))
  end

  @impl true
  def get_order_by_external_id(external_id) when is_binary(external_id) do
    result(request(:get, "/orders/@#{URI.encode(external_id)}"))
  end

  @impl true
  def get_order(printful_order_id) do
    result(request(:get, "/orders/#{printful_order_id}"))
  end

  @impl true
  def confirm_order(printful_order_id) do
    result(request(:post, "/orders/#{printful_order_id}/confirm"))
  end

  @impl true
  def cancel_order(printful_order_id) do
    result(request(:delete, "/orders/#{printful_order_id}"))
  end

  @impl true
  def set_webhooks(url, types) when is_binary(url) and is_list(types) do
    result(request(:post, "/webhooks", json: %{url: url, types: types}))
  end

  @impl true
  def get_webhooks do
    result(request(:get, "/webhooks"))
  end

  ## HTTP

  defp result({:ok, %{"result" => result}}), do: {:ok, result}

  defp result({:ok, _}),
    do: {:error, invalid("Unexpected response from Printful")}

  defp result({:error, _} = error), do: error

  defp request(method, path, opts \\ []) do
    case token() do
      nil ->
        {:error,
         %Error{
           type: :not_configured,
           message: "PRINTFUL_API_TOKEN is not configured"
         }}

      token ->
        req_opts =
          [
            method: method,
            url: @api_base_url <> path,
            auth: {:bearer, token},
            headers: store_headers(),
            retry: :transient,
            max_retries: 2,
            receive_timeout: 30_000
          ]
          |> Keyword.merge(opts)
          |> Keyword.merge(Application.get_env(:ysc, :printful_req_options, []))

        req_opts |> Req.request() |> handle_response(method, path)
    end
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}, _, _)
       when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{} = response}, method, path) do
    error = error_from_response(response)

    # 4xx are expected business outcomes (bad address, unknown order); only
    # surface unexpected ones to Sentry.
    if error.type in [:server, :auth] do
      Ysc.Logging.error("Printful API error",
        extra: %{
          method: method,
          path: path,
          status: response.status,
          message: error.message
        }
      )
    else
      Ysc.Logging.warning("Printful API request failed",
        method: method,
        path: path,
        status: response.status,
        message: error.message
      )
    end

    {:error, error}
  end

  defp handle_response({:error, exception}, method, path) do
    Ysc.Logging.warning("Printful API network error",
      method: method,
      path: path,
      error: Exception.message(exception)
    )

    {:error,
     %Error{
       type: :network,
       message: "Network error: #{Exception.message(exception)}"
     }}
  end

  @doc false
  def error_from_response(%Req.Response{status: status, body: body} = response) do
    message = error_message(body) || "Printful returned HTTP #{status}"

    type =
      cond do
        status == 429 -> :rate_limited
        status in [401, 403] -> :auth
        status == 404 -> :not_found
        status >= 500 -> :server
        true -> :invalid
      end

    %Error{
      type: type,
      status: status,
      message: message,
      retry_after: retry_after(response)
    }
  end

  defp error_message(%{"error" => %{"message" => message}})
       when is_binary(message),
       do: message

  defp error_message(%{"result" => result}) when is_binary(result), do: result
  defp error_message(_), do: nil

  defp retry_after(%Req.Response{} = response) do
    with [value | _] <- Req.Response.get_header(response, "retry-after"),
         {seconds, _} <- Integer.parse(value) do
      seconds
    else
      _ -> nil
    end
  end

  defp invalid(message), do: %Error{type: :invalid, message: message}

  defp store_headers do
    case config(:store_id) do
      nil -> []
      store_id -> [{"x-pf-store-id", to_string(store_id)}]
    end
  end

  defp token, do: config(:api_token)

  defp config(key) do
    :ysc |> Application.get_env(:printful, []) |> Keyword.get(key)
  end
end
