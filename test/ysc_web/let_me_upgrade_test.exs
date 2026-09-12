defmodule YscWeb.LetMeUpgradeTest do
  @moduledoc """
  Guards the let_me 3.0.3 → 3.0.4 upgrade.

  3.0.4 is a patch: literal `allow true` / `deny true` rules call
  `Spek.eval?/2` instead of inlining booleans so Elixir 1.20 does not
  warn about dead `authorize?/4` branches. Missing-rule warnings put the
  policy and check modules in the log message instead of Logger metadata.
  The DSL, check-function arity, and default `{:error, :unauthorized}`
  return value are unchanged. Spek stays at 0.5.0.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias LetMe.Builder
  alias Spek.AllOf
  alias Spek.Check
  alias Spek.Literal
  alias Ysc.Accounts.User
  alias YscWeb.Authorization.Policy
  alias YscWeb.Authorization.Policy.Checks

  @builder Path.expand("../../deps/let_me/lib/let_me/builder.ex", __DIR__)

  setup do
    Code.ensure_loaded!(Policy)
    Code.ensure_loaded!(Builder)
    :ok
  end

  describe "3.0.4 Hex lock and public APIs" do
    test "locks let_me to 3.0.4 and spek to 0.5.0" do
      assert to_string(Application.spec(:let_me, :vsn)) == "3.0.4"
      assert to_string(Application.spec(:spek, :vsn)) == "0.5.0"
    end

    test "authorize, authorize?, and expression helpers we use still exist" do
      assert function_exported?(Policy, :authorize, 2)
      assert function_exported?(Policy, :authorize, 3)
      assert function_exported?(Policy, :authorize, 4)
      assert function_exported?(Policy, :authorize?, 2)
      assert function_exported?(Policy, :authorize?, 3)
      assert function_exported?(Policy, :list_rules, 0)
      assert function_exported?(Policy, :fetch_expression, 1)
      assert function_exported?(Policy, :fetch_expression!, 1)
      assert function_exported?(Policy, :get_expression, 1)
    end

    test "Builder result helpers used to avoid inlined-boolean warnings exist" do
      assert {:module, Builder} = Code.ensure_loaded(Builder)
      assert function_exported?(Builder, :__result__, 2)
      assert function_exported?(Builder, :__detailed_result__, 1)
      assert function_exported?(Builder, :__ensure_authorized__, 1)
    end
  end

  describe "authorize/4 return values" do
    test "still returns :ok and {:error, :unauthorized}" do
      admin = %User{role: :admin}
      member = %User{role: :member}

      assert :ok = Policy.authorize(:post_create, admin)
      assert {:error, :unauthorized} = Policy.authorize(:post_create, member)
      assert Policy.authorize?(:post_create, admin)
      refute Policy.authorize?(:post_create, member)
    end

    test "role and own_resource checks still evaluate" do
      owner_id = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      owner = %User{id: owner_id, role: :member}
      other = %User{id: "01BX5ZZKBKACTAV9WEVGEMMVRZ", role: :member}

      assert Checks.role(admin_user(), nil, :admin)
      refute Checks.role(owner, nil, :admin)
      assert Checks.own_resource(owner, %{user_id: owner_id})
      refute Checks.own_resource(other, %{user_id: owner_id})

      assert :ok = Policy.authorize(:user_read, owner, %{user_id: owner_id})

      assert {:error, :unauthorized} =
               Policy.authorize(:user_read, other, %{user_id: owner_id})
    end
  end

  describe "3.0.4 literal allow and deny" do
    test "allow true still authorizes any subject" do
      member = %User{role: :member}

      assert :ok = Policy.authorize(:post_read, member)
      assert Policy.authorize?(:post_read, member)
      assert :ok = Policy.authorize!(:post_read, member)
    end

    test "deny true still rejects any subject" do
      admin = %User{role: :admin}

      assert {:error, :unauthorized} = Policy.authorize(:post_delete, admin)
      refute Policy.authorize?(:post_delete, admin)

      assert_raise LetMe.UnauthorizedError, fn ->
        Policy.authorize!(:post_delete, admin)
      end
    end

    test "literal rules compile to Spek.Literal and eval without inlining" do
      assert %Literal{satisfied?: true} =
               allow = Policy.get_expression(:post_read)

      assert %Literal{satisfied?: false} =
               deny = Policy.get_expression(:post_delete)

      assert Spek.eval?(allow, [])
      refute Spek.eval?(deny, [])
    end

    test "builder evaluates literals via Spek instead of inlining booleans" do
      source = File.read!(@builder)

      assert source =~ "Spek.eval?(unquote(Macro.escape(literal)), [])"
      assert source =~ "Spek.eval_tree(unquote(Macro.escape(literal)), [])"
      assert source =~ "The literal is evaluated here instead of being inlined"
    end
  end

  describe "3.0.4 missing-rule warnings" do
    test "unknown action still returns unauthorized and logs policy modules" do
      admin = %User{role: :admin}

      log =
        capture_log(fn ->
          refute Policy.authorize?(:not_a_real_action, admin)

          assert {:error, :unauthorized} =
                   Policy.authorize(:not_a_real_action, admin)
        end)

      assert log =~
               "Permission checked for a rule that does not exist: not_a_real_action"

      assert log =~ "policy: YscWeb.Authorization.Policy"
      assert log =~ "checks: YscWeb.Authorization.Policy.Checks"
    end

    test "warning message includes modules instead of Logger metadata keys" do
      source = File.read!(@builder)

      assert source =~ ~S[(policy: #{inspect(__MODULE__)},]
      assert source =~ ~S[checks: #{inspect(unquote(check_module))}]
      refute source =~ "policy_module: __MODULE__"
      refute source =~ "check_module: unquote(check_module)"
    end
  end

  describe "compiled expressions still use Spek structs" do
    test "role allow compiles to Spek.Check with ctx args" do
      assert {:ok, %Check{} = check} =
               Policy.fetch_expression(:media_image_create)

      assert check.module == Checks
      assert check.fun == :role
      assert {:ctx, :subject} in check.args
      assert :admin in check.args
    end
  end

  describe "spek 0.5.0 associativity" do
    test "optimize/1 flattens nested AllOf children" do
      a = %Check{module: Checks, fun: :role, args: [{:ctx, :subject}, :admin]}
      b = %Check{module: Checks, fun: :role, args: [{:ctx, :subject}, :member]}

      c = %Check{
        module: Checks,
        fun: :role,
        args: [{:ctx, :subject}, :volunteer]
      }

      nested = %AllOf{
        children: [a, %AllOf{children: [b, c]}]
      }

      assert %AllOf{children: children} = Spek.optimize(nested)
      assert children == [a, b, c]
    end
  end

  defp admin_user, do: %User{role: :admin}
end
