defmodule YscWeb.LetMeUpgradeTest do
  @moduledoc """
  Guards the let_me 3.0.2 → 3.0.3 upgrade.

  3.0.3 only requires spek ~> 0.5.0. Spek 0.5.0 flattens nested AllOf/AnyOf
  in `Spek.optimize/1` (associativity). The LetMe DSL, check-function arity,
  and default `{:error, :unauthorized}` return value are unchanged. We do
  not inspect Spek expression trees in app code.
  """
  use ExUnit.Case, async: true

  alias Spek.AllOf
  alias Spek.Check
  alias Spek.Literal
  alias Ysc.Accounts.User
  alias YscWeb.Authorization.Policy
  alias YscWeb.Authorization.Policy.Checks

  describe "3.0.3 Hex lock and public APIs" do
    test "locks let_me to 3.0.3 and spek to 0.5.0" do
      assert to_string(Application.spec(:let_me, :vsn)) == "3.0.3"
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

  describe "compiled expressions still use Spek structs" do
    test "role allow compiles to Spek.Check with ctx args" do
      assert {:ok, %Check{} = check} =
               Policy.fetch_expression(:media_image_create)

      assert check.module == Checks
      assert check.fun == :role
      assert {:ctx, :subject} in check.args
      assert :admin in check.args
    end

    test "always-allow compiles to a satisfied Spek.Literal" do
      assert %Literal{satisfied?: true} = Policy.get_expression(:post_read)
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
