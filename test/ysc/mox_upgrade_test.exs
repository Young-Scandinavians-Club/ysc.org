defmodule Ysc.MoxUpgradeTest do
  @moduledoc """
  Guards the mox 1.2.0 → 1.3.1 upgrade.

  1.3.0 is a minor: Elixir 1.15 floor, `Process.info(pid, :parent)` for
  allowances when `$callers` is missing, and clearer error messages.
  1.3.1 is a patch: shared-mode dispatch keeps expectation metadata as a
  map after an unexpected call so `verify!/0` does not crash.

  We use `defmock`, `expect`, `stub`, `stub_with`, `verify!`,
  `set_mox_global` (`mox_global_first` on LiveView cases),
  `set_mox_from_context`, and `verify_on_exit!`. Public APIs are unchanged.
  """
  use ExUnit.Case, async: false

  alias Ysc.Alerts.DiscordHttpMock

  @mox Path.expand("../../deps/mox/lib/mox.ex", __DIR__)

  setup do
    on_exit(fn -> Mox.set_mox_private() end)
    Mox.set_mox_private()
    :ok
  end

  describe "1.3.1 Hex lock and public APIs" do
    test "locks the Hex package to 1.3.1" do
      assert to_string(Application.spec(:mox, :vsn)) == "1.3.1"
    end

    test "expect, stub, stub_with, verify, allow, and mode helpers still exist" do
      assert function_exported?(Mox, :expect, 3)
      assert function_exported?(Mox, :expect, 4)
      assert function_exported?(Mox, :stub, 3)
      assert function_exported?(Mox, :stub_with, 2)
      assert function_exported?(Mox, :verify!, 0)
      assert function_exported?(Mox, :verify!, 1)
      assert function_exported?(Mox, :allow, 3)
      assert function_exported?(Mox, :deny, 3)
      assert function_exported?(Mox, :set_mox_global, 0)
      assert function_exported?(Mox, :set_mox_global, 1)
      assert function_exported?(Mox, :set_mox_private, 0)
      assert function_exported?(Mox, :set_mox_private, 1)
      assert function_exported?(Mox, :set_mox_from_context, 1)
      assert function_exported?(Mox, :verify_on_exit!, 0)
      assert function_exported?(Mox, :verify_on_exit!, 1)
    end

    test "mix.exs Elixir 1.20 meets the 1.3.0 Elixir 1.15 floor" do
      mix_exs = File.read!(Path.expand("../../deps/mox/mix.exs", __DIR__))
      assert mix_exs =~ ~s(elixir: "~> 1.15")
      assert Version.match?(System.version(), "~> 1.20")
    end
  end

  describe "1.3.0 parent PID allowances" do
    test "spawned child without $callers uses the parent process expectations" do
      Mox.expect(DiscordHttpMock, :send_webhook, fn url, body, headers ->
        assert url == "https://example.test/webhook"
        assert body == "{}"
        assert headers == []
        {:ok, :from_parent}
      end)

      parent = self()
      ref = make_ref()

      spawn(fn ->
        refute Process.get(:"$callers")

        result =
          DiscordHttpMock.send_webhook("https://example.test/webhook", "{}", [])

        send(parent, {ref, result})
      end)

      assert_receive {^ref, {:ok, :from_parent}}, 1_000
      Mox.verify!()
    end

    test "Process.info/2 :parent is available on this OTP" do
      parent = self()

      pid =
        spawn(fn ->
          send(parent, {:parent_info, Process.info(self(), :parent)})

          receive do
            :stop -> :ok
          end
        end)

      assert_receive {:parent_info, {:parent, ^parent}}, 1_000
      send(pid, :stop)
    end
  end

  describe "1.3.1 shared-mode verify after unexpected call" do
    test "verify! does not crash after UnexpectedCallError in global mode" do
      Mox.set_mox_global()

      assert_raise Mox.UnexpectedCallError, fn ->
        DiscordHttpMock.send_webhook("https://example.test/missing", "{}", [])
      end

      assert Mox.verify!() == :ok
    end

    test "dispatch stores an empty map instead of nil after a shared miss" do
      source = File.read!(@mox)

      assert source =~
               "# In shared mode, fetch_owner_from_callers/2 returns the shared owner even when the"

      assert source =~ "{:no_expectation, %{}}"
    end
  end

  describe "existing call sites" do
    test "mox_global_first LiveViews still opt into shared mode before stubs" do
      conn_case =
        File.read!(Path.expand("../../test/support/conn_case.ex", __DIR__))

      assert conn_case =~ "Mox.set_mox_global()"
      assert conn_case =~ "Mox.set_mox_private()"

      data_case =
        File.read!(Path.expand("../../test/support/data_case.ex", __DIR__))

      assert data_case =~ "stub_with(Stripe.PaymentMethodMock"
      assert data_case =~ "stub_with(Stripe.SubscriptionMock"
    end
  end
end
