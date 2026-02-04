defmodule Ysc.Keila.Client do
  @moduledoc """
  Implementation of Keila API interactions using Req.
  """
  @behaviour Ysc.Keila.Behaviour

  require Logger

  @impl true
  def subscribe_email(email, opts) do
    form_id = opts[:form_id] || get_config(:form_id)
    api_url = get_config(:api_url)
    api_key = get_config(:api_key)

    cond do
      is_nil(api_url) || is_nil(api_key) ->
        {:error, :not_configured}

      is_nil(form_id) ->
        {:error, :not_configured}

      true ->
        url = "#{api_url}/api/v1/forms/#{form_id}/actions/submit"
        headers = [{"Authorization", "Bearer #{api_key}"}]

        # Build the data payload
        data = %{"email" => email}

        # Add first_name if provided
        data =
          if opts[:first_name],
            do: Map.put(data, "first_name", opts[:first_name]),
            else: data

        # Add last_name if provided
        data =
          if opts[:last_name],
            do: Map.put(data, "last_name", opts[:last_name]),
            else: data

        # Add custom metadata if provided
        data =
          if opts[:data], do: Map.put(data, "data", opts[:data]), else: data

        body = %{"data" => data}

        case Req.post(url, headers: headers, json: body) do
          {:ok, %{status: status}} when status in 200..299 ->
            :ok

          {:ok, %{status: status}} ->
            {:error, "Keila API error: #{status}"}

          {:error, _} ->
            {:error, :network_error}
        end
    end
  end

  @impl true
  def unsubscribe_email(email, _opts) do
    api_url = get_config(:api_url)
    api_key = get_config(:api_key)

    cond do
      is_nil(api_url) || is_nil(api_key) ->
        {:error, :not_configured}

      true ->
        # Keila API: Get contact by email
        search_url = "#{api_url}/api/v1/contacts/#{email}"
        headers = [{"Authorization", "Bearer #{api_key}"}]

        case Req.get(search_url, headers: headers, params: [id_type: "email"]) do
          {:ok, %{status: 200, body: %{"data" => contact}}} ->
            # Update contact to unsubscribed
            contact_id = contact["id"]
            update_url = "#{api_url}/api/v1/contacts/#{contact_id}"

            case Req.put(update_url,
                   headers: headers,
                   json: %{"data" => %{"status" => "unsubscribed"}}
                 ) do
              {:ok, %{status: status}} when status in 200..299 -> :ok
              {:ok, %{status: status}} -> {:error, "Keila API error: #{status}"}
            end

          {:ok, %{status: 404}} ->
            :ok

          {:ok, %{status: status}} ->
            {:error, "Keila API error: #{status}"}

          {:error, _} ->
            {:error, :network_error}
        end
    end
  end

  @impl true
  def get_subscription_status(email, _opts) do
    api_url = get_config(:api_url)
    api_key = get_config(:api_key)

    cond do
      is_nil(api_url) || is_nil(api_key) ->
        {:error, :not_configured}

      true ->
        url = "#{api_url}/api/v1/contacts/#{email}"
        headers = [{"Authorization", "Bearer #{api_key}"}]

        case Req.get(url, headers: headers, params: [id_type: "email"]) do
          {:ok, %{status: 200, body: %{"data" => contact}}} ->
            status = normalize_keila_status(contact["status"])
            {:ok, status}

          {:ok, %{status: 404}} ->
            {:ok, :not_found}

          {:ok, %{status: status}} ->
            {:error, "Keila API error: #{status}"}

          {:error, _} ->
            {:error, :network_error}
        end
    end
  end

  # Maps Keila status strings to known atoms to prevent atom exhaustion
  defp normalize_keila_status("active"), do: :active
  defp normalize_keila_status("unsubscribed"), do: :unsubscribed
  defp normalize_keila_status("unreachable"), do: :unreachable
  defp normalize_keila_status("pending"), do: :pending
  defp normalize_keila_status(_unknown), do: :active

  defp get_config(key) do
    Application.get_env(:ysc, :keila, [])[key]
  end
end
