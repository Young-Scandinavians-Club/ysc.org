defmodule Ysc.Stripe.IdempotencyTest do
  use ExUnit.Case, async: true

  alias Ysc.Stripe.Idempotency

  describe "key/1" do
    test "returns short keys unchanged" do
      assert Idempotency.key("customer_create_01ARZ3NDEKTSV4RRFFQ69G5FAV") ==
               "customer_create_01ARZ3NDEKTSV4RRFFQ69G5FAV"
    end

    test "returns a key at exactly the limit unchanged" do
      key = String.duplicate("a", 255)
      assert Idempotency.key(key) == key
    end

    test "truncates keys over Stripe's 255-character limit" do
      long_key = String.duplicate("a", 300)

      result = Idempotency.key(long_key)

      assert String.length(result) == 255
      assert String.starts_with?(result, String.duplicate("a", 238) <> "_")
    end

    test "produces different results for long keys that only differ near the end" do
      base = String.duplicate("a", 260)

      result_a = Idempotency.key(base <> "_order_1")
      result_b = Idempotency.key(base <> "_order_2")

      assert result_a != result_b
      assert String.length(result_a) == 255
      assert String.length(result_b) == 255
    end

    test "is deterministic for the same input" do
      long_key = String.duplicate("x", 400) <> "_tail"

      assert Idempotency.key(long_key) == Idempotency.key(long_key)
    end
  end
end
