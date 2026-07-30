defmodule Lotus.Web.Helpers do
  @moduledoc false

  # Loaded at runtime by QueryConsole.LotusWeb.HelpersPatch (not compiled into
  # query_console) so mix release does not see a duplicate module with lotus_web.
  # Fixes root-mounted path joins: "" → "/", "queries/new" → "/queries/new".

  alias Phoenix.VerifiedRoutes

  @pdict_key :__lotus_web_prefix__

  @doc false
  def __query_console_patched__, do: true

  @doc false
  def put_router_prefix(socket, prefix) do
    Process.put(@pdict_key, {socket, prefix})
  end

  @doc false
  def lotus_path(route, params \\ %{})

  def lotus_path(route, params) when is_list(route) do
    route
    |> Enum.join("/")
    |> lotus_path(params)
  end

  def lotus_path(route, params) do
    params =
      params
      |> Enum.sort()
      |> encode_params()

    case Process.get(@pdict_key) do
      {socket, prefix} ->
        path = join_prefix(prefix, route)
        VerifiedRoutes.unverified_path(socket, socket.router, path, params)

      :nowhere ->
        "/"

      nil ->
        raise RuntimeError, "nothing stored in the #{@pdict_key} key"
    end
  end

  defp join_prefix(prefix, route) when route in ["", nil] do
    case prefix do
      p when p in ["", "/"] -> "/"
      p when is_binary(p) -> p
    end
  end

  defp join_prefix(prefix, route) when prefix in ["", "/"], do: "/" <> to_string(route)

  defp join_prefix(prefix, route) when is_binary(prefix) do
    String.trim_trailing(prefix, "/") <> "/" <> to_string(route)
  end

  def encode_params(params) do
    for {key, val} <- params, val != nil, val != "" do
      case val do
        [path, frag] when is_list(path) ->
          {key, Enum.join(path, ",") <> "++" <> frag}

        [_ | _] ->
          {key, Enum.join(val, ",")}

        _ ->
          {key, val}
      end
    end
  end

  def decode_params(params) do
    Map.new(params, fn
      {"limit", val} ->
        {:limit, String.to_integer(val)}

      {key, val} when key in ~w(args meta) ->
        val =
          val
          |> String.split("++")
          |> List.update_at(0, &String.split(&1, ","))

        {String.to_existing_atom(key), val}

      {key, val} when key in ~w(ids modes nodes priorities queues stats tags workers) ->
        {String.to_existing_atom(key), String.split(val, ",")}

      {key, val} ->
        {String.to_existing_atom(key), val}
    end)
  end

  def active_filter?(params, :state, value) do
    params[:state] == value or (is_nil(params[:state]) and value == "executing")
  end

  def active_filter?(params, key, value) do
    params
    |> Map.get(key, [])
    |> List.wrap()
    |> Enum.member?(to_string(value))
  end

  require Logger

  def safe_json_encode(data) do
    {:ok, Lotus.JSON.encode!(data)}
  rescue
    error ->
      Logger.warning("JSON encoding failed: #{Exception.message(error)}")
      {:error, :encoding_failed}
  end

  def safe_json_encode_or_empty(data) do
    Lotus.JSON.encode!(data)
  rescue
    error ->
      Logger.warning("JSON encoding failed: #{Exception.message(error)}")
      "{}"
  end
end
