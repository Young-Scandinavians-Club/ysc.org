defmodule Ysc.HttpTestServer do
  @moduledoc """
  Shared Plug.Cowboy servers for tests (one server per named plug, reused across tests).
  """

  use Agent

  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{} end, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Returns the port for a running server, starting Cowboy once per `name` if needed.
  """
  def ensure_started(plug_module, name)
      when is_atom(name) and is_atom(plug_module) do
    Agent.get_and_update(__MODULE__, fn servers ->
      case Map.fetch(servers, name) do
        {:ok, port} ->
          {port, servers}

        :error ->
          {port, _ref} = start_cowboy!(plug_module, name)
          {port, Map.put(servers, name, port)}
      end
    end)
  end

  defp start_cowboy!(plug_module, name) do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)

    ref = :"http_test_#{name}_#{port}"

    {:ok, _} = Plug.Cowboy.http(plug_module, [], port: port, ref: ref)

    {port, ref}
  end
end
