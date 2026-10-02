defmodule Ysc.DnsClusterUpgradeTest do
  @moduledoc """
  Guards the dns_cluster 0.3.0 → 0.3.1 upgrade.

  0.3.1 is a patch with no documented breaking changes. `discover_ips/1`
  used to unwrap a `{basename, query}` tuple for the node basename but
  still passed the whole tuple to `Resolver.lookup/2`, whose clauses
  only match binaries. The documented tuple form therefore raised
  `FunctionClauseError` on the first poll.

  0.3.1 looks up the hostname instead. We start
  `{DNSCluster, query: Application.get_env(:ysc, :dns_cluster_query) || :ignore}`
  with a string (`DNS_CLUSTER_QUERY=${FLY_APP_NAME}.internal`) or
  `:ignore`, not a tuple, so the fix is unused. Public APIs are
  unchanged. 0.3.0 `:resource_types` (default `[:a, :aaaa]`) still
  applies.
  """
  use ExUnit.Case, async: false

  @mailbox :dns_cluster_upgrade_mailbox
  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/dns_cluster/CHANGELOG.md", __DIR__)
  @cluster Path.expand("../../deps/dns_cluster/lib/dns_cluster.ex", __DIR__)
  @resolver Path.expand(
              "../../deps/dns_cluster/lib/dns_cluster/resolver.ex",
              __DIR__
            )
  @application Path.expand("../../lib/ysc/application.ex", __DIR__)
  @runtime Path.expand("../../config/runtime.exs", __DIR__)
  @rel_env Path.expand("../../rel/env.sh.eex", __DIR__)

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

  setup_all do
    {:ok, _} = Application.ensure_all_started(:dns_cluster)
    {:module, DNSCluster} = Code.ensure_loaded(DNSCluster)
    {:module, DNSCluster.Resolver} = Code.ensure_loaded(DNSCluster.Resolver)
    :ok
  end

  setup do
    :persistent_term.put(@mailbox, self())
    :ok
  end

  describe "0.3.1 Hex lock and public APIs" do
    test "locks dns_cluster to 0.3.1" do
      assert to_string(Application.spec(:dns_cluster, :vsn)) == "0.3.1"
    end

    test "mix.exs pins the 0.3.1 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:dns_cluster, "~> 0.3.1"}|
    end

    test "companion lock is 0.3.1" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"dns_cluster": {:hex, :dns_cluster, "0.3.1"|
    end

    test "start_link/1 and Resolver still load" do
      assert {:module, _} = Code.ensure_loaded(DNSCluster)
      assert function_exported?(DNSCluster, :start_link, 1)

      assert {:module, DNSCluster.Resolver} =
               Code.ensure_loaded(DNSCluster.Resolver)

      assert function_exported?(DNSCluster.Resolver, :lookup, 2)
      assert function_exported?(DNSCluster.Resolver, :basename, 1)
      assert function_exported?(DNSCluster.Resolver, :connect_node, 1)
      assert function_exported?(DNSCluster.Resolver, :list_nodes, 0)
    end
  end

  describe "0.3.1 changelog" do
    test "documents the {basename, query} hostname lookup fix" do
      changelog = File.read!(@changelog)

      v031 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "0.3.1"))

      assert v031

      assert v031 =~
               "Properly look up the hostname of a {basename, query} tuple"

      refute v031 =~ "Breaking"
    end
  end

  describe "0.3.1 looks up hostname of {basename, query} tuples" do
    test "discover_ips passes the hostname, not the tuple, to lookup/2" do
      source = File.read!(@cluster)

      assert source =~
               "{basename, hostname} = basename_and_hostname(query, state)"

      assert source =~ "addr <- resolver.lookup(hostname, resource_type)"
      refute source =~ "basename_from_query_or_state"
      refute source =~ "addr <- resolver.lookup(query, resource_type)"
    end

    test "real Resolver.lookup/2 still only matches binary hostnames" do
      source = File.read!(@resolver)

      assert source =~
               "def lookup(query, type) when is_binary(query) and type in [:a, :aaaa]"

      assert source =~
               "def lookup(query, type) when is_binary(query) and type in [:srv]"
    end

    test "tuple query looks up the hostname and connects with that basename" do
      {:ok, cluster} =
        start_supervised(
          {DNSCluster,
           name: :dns_cluster_upgrade_tuple,
           query: {"remote", "remote-app.internal"},
           resolver: __MODULE__,
           interval: 60_000}
        )

      :sys.get_state(cluster)

      remote_new = :"remote@#{@ips.new}"
      assert_receive {:try_connect, ^remote_new}

      lookups = received_lookups()
      hostnames = for {:lookup, query, _type} <- lookups, do: query

      assert "remote-app.internal" in hostnames
      refute Enum.any?(hostnames, &is_tuple/1)
      refute {"remote", "remote-app.internal"} in hostnames
    end

    test "mixed string and tuple queries look up each hostname separately" do
      {:ok, cluster} =
        start_supervised(
          {DNSCluster,
           name: :dns_cluster_upgrade_mixed,
           query: ["ysc.internal", {"remote", "remote-app.internal"}],
           resolver: __MODULE__,
           interval: 60_000}
        )

      :sys.get_state(cluster)

      ysc_new = :"ysc@#{@ips.new}"
      remote_new = :"remote@#{@ips.new}"
      assert_receive {:try_connect, ^ysc_new}
      assert_receive {:try_connect, ^remote_new}

      hostnames = for {:lookup, query, _type} <- received_lookups(), do: query

      assert "ysc.internal" in hostnames
      assert "remote-app.internal" in hostnames
      refute Enum.any?(hostnames, &is_tuple/1)
    end
  end

  describe "app child spec (string query or :ignore, default A/AAAA)" do
    test "application still passes env string or :ignore, not a tuple" do
      application = File.read!(@application)
      runtime = File.read!(@runtime)
      rel_env = File.read!(@rel_env)

      assert application =~
               "query: Application.get_env(:ysc, :dns_cluster_query) || :ignore"

      assert runtime =~
               "config :ysc, dns_cluster_query: System.get_env(\"DNS_CLUSTER_QUERY\")"

      assert rel_env =~
               ~s|export DNS_CLUSTER_QUERY="${FLY_APP_NAME}.internal"|

      refute application =~ ~s|query: {"|
    end

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

  describe "0.3.0 :resource_types is still opt-in" do
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
