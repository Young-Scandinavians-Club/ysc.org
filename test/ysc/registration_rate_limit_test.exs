defmodule Ysc.RegistrationRateLimitTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ysc.DistributedCache
  alias Ysc.RateLimit
  alias Ysc.RegistrationRateLimit

  # Unique IP per test so the shared ETS buckets don't collide.
  defp unique_test_ip do
    n = System.unique_integer([:positive])
    {10, rem(div(n, 256 * 256), 254) + 1, rem(div(n, 256), 256), rem(n, 256)}
  end

  # The +1/-1 this node broadcast for `reservation`, so a test can replay it
  # as if another node had sent it.
  defp assert_broadcast!({ip, window}, op) do
    key = {"registration:" <> ip, window}

    assert_receive {:distributed_counter_update, _node, RegistrationRateLimit,
                    ^key, ^op, _default} = update

    update
  end

  defp apply_from_other_node(
         {:distributed_counter_update, _node, table, key, op, default}
       ) do
    send(
      DistributedCache.Sync,
      {:distributed_counter_update, :other@nohost, table, key, op, default}
    )

    # Sync handles its mailbox in order, so this waits for the update above.
    :sys.get_state(DistributedCache.Sync)
  end

  defp reserve_up_to_limit!(ip) do
    for _ <- 1..RegistrationRateLimit.ip_limit() do
      assert {:ok, _reservation} = RegistrationRateLimit.reserve_application(ip)
    end
  end

  describe "ip_limit/0" do
    test "reads the configured limit" do
      # config/test.exs raises it so LiveView tests from 127.0.0.1 aren't limited.
      assert RegistrationRateLimit.ip_limit() == 10_000
    end
  end

  describe "reserve_application/1" do
    test "reserves up to the limit, then rate limits" do
      ip = unique_test_ip()
      reserve_up_to_limit!(ip)

      assert {:error, :rate_limited, retry_after_seconds} =
               RegistrationRateLimit.reserve_application(ip)

      assert retry_after_seconds in 1..3600
    end

    test "simultaneous reservations can't exceed the limit" do
      ip = unique_test_ip()
      limit = RegistrationRateLimit.ip_limit()

      results =
        1..(limit + 50)
        |> Task.async_stream(
          fn _ -> RegistrationRateLimit.reserve_application(ip) end,
          max_concurrency: System.schedulers_online() * 4,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &match?({:ok, _}, &1)) == limit
    end

    test "limits each IP separately" do
      ip = unique_test_ip()
      reserve_up_to_limit!(ip)

      assert {:error, :rate_limited, _} =
               RegistrationRateLimit.reserve_application(ip)

      assert {:ok, _} =
               RegistrationRateLimit.reserve_application(unique_test_ip())
    end

    test "treats string and tuple forms of an IP as the same bucket" do
      ip = unique_test_ip()
      reserve_up_to_limit!(ip |> :inet.ntoa() |> to_string())

      assert {:error, :rate_limited, _} =
               RegistrationRateLimit.reserve_application(ip)
    end

    test "logs a warning with the IP when over the limit" do
      ip = unique_test_ip()
      reserve_up_to_limit!(ip)

      log =
        capture_log(
          [format: "$message $metadata", metadata: [:ip, :limit]],
          fn -> RegistrationRateLimit.reserve_application(ip) end
        )

      assert log =~ "Membership application rate limit exceeded by IP"
      assert log =~ "ip=#{:inet.ntoa(ip)}"
    end
  end

  describe "release_application/1" do
    test "gives back a reserved slot" do
      ip = unique_test_ip()

      for _ <- 1..(RegistrationRateLimit.ip_limit() - 1) do
        RegistrationRateLimit.reserve_application(ip)
      end

      {:ok, reservation} = RegistrationRateLimit.reserve_application(ip)

      assert :ok = RegistrationRateLimit.release_application(reservation)
      assert {:ok, _} = RegistrationRateLimit.reserve_application(ip)

      assert {:error, :rate_limited, _} =
               RegistrationRateLimit.reserve_application(ip)
    end

    test "does nothing for a reservation from an earlier hour" do
      ip = unique_test_ip()

      for _ <- 1..(RegistrationRateLimit.ip_limit() - 1) do
        RegistrationRateLimit.reserve_application(ip)
      end

      {:ok, {normalized_ip, window}} =
        RegistrationRateLimit.reserve_application(ip)

      # Counters are keyed by the reservation's hour, so a release that
      # arrives after that hour ended can't free a slot in the current one.
      assert :ok =
               RegistrationRateLimit.release_application(
                 {normalized_ip, window - 1}
               )

      assert {:error, :rate_limited, _} =
               RegistrationRateLimit.reserve_application(ip)
    end
  end

  describe "across nodes" do
    setup do
      Phoenix.PubSub.subscribe(Ysc.PubSub, DistributedCache.topic())
      :ok
    end

    test "counts slots taken on other nodes" do
      ip = unique_test_ip()
      {:ok, reservation} = RegistrationRateLimit.reserve_application(ip)

      # Replaying this node's +1 stands in for another node taking a slot for
      # the same IP, which uses one up here too.
      reservation |> assert_broadcast!({2, 1}) |> apply_from_other_node()

      for _ <- 1..(RegistrationRateLimit.ip_limit() - 2) do
        assert {:ok, _} = RegistrationRateLimit.reserve_application(ip)
      end

      assert {:error, :rate_limited, _} =
               RegistrationRateLimit.reserve_application(ip)
    end

    test "frees slots released on other nodes" do
      ip = unique_test_ip()

      for _ <- 1..(RegistrationRateLimit.ip_limit() - 1) do
        RegistrationRateLimit.reserve_application(ip)
      end

      {:ok, reservation} = RegistrationRateLimit.reserve_application(ip)
      RegistrationRateLimit.release_application(reservation)

      # Replaying this node's -1 stands in for another node releasing a slot
      # for the same IP, which frees one here too.
      reservation |> assert_broadcast!({2, -1, 0, 0}) |> apply_from_other_node()

      assert {:ok, _} = RegistrationRateLimit.reserve_application(ip)
      assert {:ok, _} = RegistrationRateLimit.reserve_application(ip)

      assert {:error, :rate_limited, _} =
               RegistrationRateLimit.reserve_application(ip)
    end

    test "only broadcasts kept slots" do
      ip = unique_test_ip()
      reserve_up_to_limit!(ip)

      assert {:error, :rate_limited, _} =
               RegistrationRateLimit.reserve_application(ip)

      ip_key = "registration:" <> RateLimit.normalize_ip(ip)

      assert drain_updates(ip_key) ==
               List.duplicate({2, 1}, RegistrationRateLimit.ip_limit())
    end
  end

  # Every counter op this node broadcast for `ip_key`, oldest first.
  defp drain_updates(ip_key, acc \\ []) do
    receive do
      {:distributed_counter_update, _node, RegistrationRateLimit,
       {^ip_key, _window}, op, _default} ->
        drain_updates(ip_key, [op | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
