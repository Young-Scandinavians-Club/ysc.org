defmodule Ysc.EnvTest do
  use ExUnit.Case, async: true

  describe "current/0" do
    test "returns the configured environment as an atom" do
      assert Ysc.Env.current() == :test
    end

    test "handles string environment configuration" do
      original = Application.get_env(:ysc, :environment)

      try do
        Application.put_env(:ysc, :environment, "dev")
        assert Ysc.Env.current() == :dev
      after
        Application.put_env(:ysc, :environment, original)
      end
    end

    test "handles atom environment configuration" do
      original = Application.get_env(:ysc, :environment)

      try do
        Application.put_env(:ysc, :environment, :dev)
        assert Ysc.Env.current() == :dev
      after
        Application.put_env(:ysc, :environment, original)
      end
    end
  end

  describe "test?/0" do
    test "returns true in test environment" do
      assert Ysc.Env.test?() == true
    end
  end

  describe "dev?/0" do
    test "returns false in test environment" do
      assert Ysc.Env.dev?() == false
    end
  end

  describe "prod?/0" do
    test "returns false in test environment" do
      assert Ysc.Env.prod?() == false
    end
  end

  describe "sandbox?/0" do
    test "returns false in test environment" do
      assert Ysc.Env.sandbox?() == false
    end
  end

  describe "non_prod?/0" do
    test "returns true in test environment" do
      assert Ysc.Env.non_prod?() == true
    end
  end
end
