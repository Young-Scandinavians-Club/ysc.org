defmodule YscWeb.AdminFlopHelpers do
  @moduledoc """
  Shared helpers for admin Flop list LiveViews (pagination URLs, etc.).
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
end
