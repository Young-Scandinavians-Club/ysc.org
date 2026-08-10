defmodule YscWeb.AdminFlopHelpers do
  @moduledoc """
  Shared helpers for admin Flop list LiveViews (pagination URLs, title search, etc.).
  """

  @flop_keys ~w(order_by order_directions page page_size limit offset filters)

  @doc """
  Drops Flop pagination and filter keys from route params so they can be
  re-appended by `<.admin_flop_pagination>`.
  """
  @spec non_flop_params(map() | any()) :: map()
  def non_flop_params(params) when is_map(params),
    do: Map.drop(params, @flop_keys)

  def non_flop_params(_), do: %{}

  @doc """
  Returns the current title `ilike` search query from Flop meta, or `""`.
  """
  @spec title_search_query(term()) :: String.t()
  def title_search_query(nil), do: ""

  def title_search_query(%{flop: %{filters: filters}}) when is_list(filters) do
    case Enum.find(filters, &(&1.field == :title)) do
      %{value: value} when is_binary(value) -> value
      _ -> ""
    end
  end

  def title_search_query(_), do: ""

  @doc """
  Builds indexed Flop filter params for a title search, preserving other filters.

  Accepts `nil` meta (e.g. before the first list load completes).
  """
  @spec build_title_search_filter_params(term(), String.t()) :: map()
  def build_title_search_filter_params(meta, query) do
    filters =
      case meta do
        %{flop: %{filters: filters}} when is_list(filters) -> filters
        _ -> []
      end

    filters
    |> build_title_search_filters(query)
    |> filters_to_params()
  end

  @doc """
  Replaces any existing title filter with `query`, or removes it when empty.
  """
  @spec build_title_search_filters([Flop.Filter.t()], String.t()) :: [
          Flop.Filter.t()
        ]
  def build_title_search_filters(filters, query) when is_list(filters) do
    filters
    |> Enum.reject(&(&1.field == :title))
    |> then(fn remaining ->
      if query != "" do
        [%Flop.Filter{field: :title, op: :ilike, value: query} | remaining]
      else
        remaining
      end
    end)
  end

  @doc """
  Converts Flop filters into the indexed params map used in admin list URLs.
  """
  @spec filters_to_params([Flop.Filter.t()]) :: map()
  def filters_to_params(filters) when is_list(filters) do
    filters
    |> Enum.with_index()
    |> Enum.into(%{}, fn {filter, idx} ->
      {"#{idx}",
       %{
         "field" => "#{filter.field}",
         "op" => "#{filter.op}",
         "value" => "#{filter.value}"
       }}
    end)
  end

  @doc """
  Adds non-empty `date_from` / `date_to` keys to route params.
  """
  @spec merge_date_range_into_params(map(), String.t(), String.t()) :: map()
  def merge_date_range_into_params(params, date_from, date_to) do
    params
    |> then(fn p ->
      if date_from != "", do: Map.put(p, "date_from", date_from), else: p
    end)
    |> then(fn p ->
      if date_to != "", do: Map.put(p, "date_to", date_to), else: p
    end)
  end

  @doc """
  Normalizes a single filter param map, e.g. `[""]` multi-select values to `""`.
  """
  @spec normalize_filter_value(map()) :: map()
  def normalize_filter_value(%{"value" => [""]} = filter),
    do: Map.replace(filter, "value", "")

  def normalize_filter_value(filter) when is_map(filter), do: filter

  @doc """
  Drops filter params whose value is empty after normalization.
  """
  @spec compact_filter_params(map() | nil) :: map()
  def compact_filter_params(nil), do: %{}

  def compact_filter_params(filter_params) when is_map(filter_params) do
    Enum.reduce(filter_params, %{}, fn {k, v}, acc ->
      updated = normalize_filter_value(v)

      if updated["value"] in ["", nil] do
        acc
      else
        Map.put(acc, k, updated)
      end
    end)
  end

  @doc """
  Re-applies the current title search filter from `meta` onto `updated_filters`.
  """
  @spec merge_title_filter_into_params(map(), term()) :: map()
  def merge_title_filter_into_params(updated_filters, meta)
      when is_map(updated_filters) do
    case title_filter(meta) do
      %{value: value} when is_binary(value) and value != "" ->
        next_idx = map_size(updated_filters)

        Map.put(updated_filters, "#{next_idx}", %{
          "field" => "title",
          "op" => "ilike",
          "value" => value
        })

      _ ->
        updated_filters
    end
  end

  defp title_filter(nil), do: nil

  defp title_filter(%{flop: %{filters: filters}}) when is_list(filters) do
    Enum.find(filters, &(&1.field == :title))
  end

  defp title_filter(_), do: nil
end
