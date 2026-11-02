defmodule Ysc.SeedsProdTest do
  use ExUnit.Case, async: false

  @seeds Path.expand("../../priv/repo/seeds_prod.exs", __DIR__)

  setup do
    original = System.get_env("ADMIN_PASSWORD")

    on_exit(fn ->
      if original,
        do: System.put_env("ADMIN_PASSWORD", original),
        else: System.delete_env("ADMIN_PASSWORD")
    end)

    :ok
  end

  test "aborts the seed (and so the deploy) when ADMIN_PASSWORD is unset" do
    System.delete_env("ADMIN_PASSWORD")

    assert_raise RuntimeError, ~r/ADMIN_PASSWORD is not set/, fn ->
      Code.eval_file(@seeds)
    end
  end

  test "rejects the old public placeholder and short passwords" do
    for value <- ["change_me_in_production", "short", "   "] do
      System.put_env("ADMIN_PASSWORD", value)

      assert_raise RuntimeError, ~r/ADMIN_PASSWORD must be/, fn ->
        Code.eval_file(@seeds)
      end
    end
  end
end
