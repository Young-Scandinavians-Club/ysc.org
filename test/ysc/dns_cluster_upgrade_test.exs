defmodule Ysc.DnsClusterUpgradeTest do
  @moduledoc """
  Guards the dns_cluster 0.2.0 → 0.3.0 upgrade.

  0.3.0 adds optional `:resource_types` (defaults `[:a, :aaaa]`, also `:srv`)
  and moves `DNSCluster.Resolver` to its own module. Fly 6PN discovery still
  uses `${FLY_APP_NAME}.internal` A/AAAA records (`rel/env.sh.eex`). We pass
  a string query or `:ignore` and do not set `:resource_types`.
  """
  use ExUnit.Case, async: false

  @mailbox :dns_cluster_upgrade_mailbox

  @ips %{
    already_known: ~c"fdaa:0:36c9:a7b:db:400e:1352:1",
    new: ~c"fdaa:0:36c9:a7b:db:400e:1352:2"
  }

  def basename(_node_name), do: "ysc"

  def connect_node(node_name) do
    send(:persistent_term.get(@mailbox), {:try_connect, node_name})
    true
  end

  def list_nodes do
    [:"ysc@#{@ips.already_known}"]
  end

  def lookup(query, type) when is_binary(query) and type in [:a, :aaaa, :srv] do
    send(:persistent_term.get(@mailbox), {:lookup, query, type})

    {:ok, known} = :inet.parse_address(@ips.already_known)
    {:ok, new} = :inet.parse_address(@ips.new)
    [known, new]
  end

  setup do
    :persistent_term.put(@mailbox, self())
    :ok
  end

  describe "0.3.0 Hex lock and public APIs" do
    test "locks dns_cluster to 0.3.0" do
      assert to_string(Application.spec(:dns_cluster, :vsn)) == "0.3.0"
    end

    test "start_link/1 and Resolver still load" do
      assert function_exported?(DNSCluster, :start_link, 1)

      assert {:module, DNSCluster.Resolver} =
               Code.ensure_loaded(DNSCluster.Resolver)

      assert function_exported?(DNSCluster.Resolver, :lookup, 2)
      assert function_exported?(DNSCluster.Resolver, :basename, 1)
      assert function_exported?(DNSCluster.Resolver, :connect_node, 1)
      assert function_exported?(DNSCluster.Resolver, :list_nodes, 0)
    end
  end

  describe "app child spec (string query or :ignore, default A/AAAA)" do
    test "query: :ignore still skips starting the child" do
      assert DNSCluster.start_link(query: :ignore) == :ignore
    end

    test "string query starts with default resource_types [:a, :aaaa]" do
      {:ok, cluster} =
        start_supervised(
          {DNSCluster,
           name: :dns_cluster_upgrade_default,
           query: "ysc.internal",
           resolver: __MODULE__,
           interval: 60_000}
        )

      state = :sys.get_state(cluster)

      assert state.query == ["ysc.internal"]
      assert state.resource_types == [:a, :aaaa]
      refute :srv in state.resource_types
    end

    test "discovers A and AAAA records without querying SRV" do
      {:ok, cluster} =
        start_supervised(
          {DNSCluster,
           name: :dns_cluster_upgrade_discover,
           query: "ysc.internal",
           resolver: __MODULE__,
           interval: 60_000}
        )

      :sys.get_state(cluster)

      new_node = :"ysc@#{@ips.new}"
      assert_receive {:try_connect, ^new_node}

      types =
        for {:lookup, "ysc.internal", type} <- received_lookups(), do: type

      assert :a in types
      assert :aaaa in types
      refute :srv in types
    end
  end

  describe "0.3.0 :resource_types is opt-in" do
    test "accepts a subset that includes :srv" do
      assert {:ok, _cluster} =
               start_supervised(
                 {DNSCluster,
                  name: :dns_cluster_upgrade_srv,
                  query: "ysc.internal",
                  resource_types: [:a, :srv],
                  resolver: __MODULE__,
                  interval: 60_000}
               )
    end

    test "rejects an empty resource_types list" do
      assert_raise RuntimeError,
                   ~r/expected :resource_types to be a subset of \[:a, :aaaa, :srv\]/,
                   fn ->
                     start_supervised!(
                       {DNSCluster,
                        name: :dns_cluster_upgrade_empty_types,
                        query: "ysc.internal",
                        resource_types: [],
                        resolver: __MODULE__}
                     )
                   end
    end
  end

  defp received_lookups do
    {:messages, messages} = Process.info(self(), :messages)
    Enum.filter(messages, &match?({:lookup, _, _}, &1))
  end
end
