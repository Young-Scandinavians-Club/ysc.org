defmodule Ysc.NestedFilterUpgradeTest do
  @moduledoc """
  Guards the nested_filter 2.1.0 → 2.2.0 upgrade.

  2.2.0 is a minor: `filter/3` and `take_by_key/3` accept `empties: :prune`
  (default, same as 2.1.0) or `:keep`; `compact/2` uses the same option as
  the canonical spelling for empty-container handling; `compact/2`'s
  boolean `prune_empty` is a deprecated alias and will be removed in 3.0.
  Passing both `:empties` and `:prune_empty` raises `ArgumentError`.

  We do not call `filter/3`, `take_by_key/3`, or `compact/2` in app code.
  Passbook.Pass.generate_json/1 uses `drop_by_key/2` then `drop_by_value/2`
  (arity-2, default opts). Those are sugar over `reject/3`, which is
  unchanged and does not take `:empties`.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @nested_filter Path.expand(
                   "../../deps/nested_filter/lib/nested_filter.ex",
                   __DIR__
                 )
  @passbook_pass Path.expand("../../deps/passbook/lib/pass.ex", __DIR__)

  setup_all do
    {:module, NestedFilter} = Code.ensure_loaded(NestedFilter)
    :ok
  end

  describe "2.2.0 Hex lock and public APIs" do
    test "locks the Hex package to 2.2.0" do
      assert to_string(Application.spec(:nested_filter, :vsn)) == "2.2.0"
    end

    test "mix.exs override pins the 2.2 floor above passbook's 1.2.2" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:nested_filter, "~> 2.2", override: true})
    end

    test "passbook still calls drop_by_key/2 then drop_by_value/2" do
      source = File.read!(@passbook_pass)

      assert source =~ ~s|NestedFilter.drop_by_key(["__struct__"])|
      assert source =~ ~s|NestedFilter.drop_by_value([nil, %{}])|
    end

    test "drop, take, compact, and engine APIs passbook and 2.2.0 use still exist" do
      assert {:module, _} = Code.ensure_loaded(NestedFilter)
      assert function_exported?(NestedFilter, :drop_by_key, 2)
      assert function_exported?(NestedFilter, :drop_by_key, 3)
      assert function_exported?(NestedFilter, :drop_by_value, 2)
      assert function_exported?(NestedFilter, :drop_by_value, 3)
      assert function_exported?(NestedFilter, :take_by_key, 2)
      assert function_exported?(NestedFilter, :take_by_key, 3)
      assert function_exported?(NestedFilter, :compact, 1)
      assert function_exported?(NestedFilter, :compact, 2)
      assert function_exported?(NestedFilter, :filter, 2)
      assert function_exported?(NestedFilter, :filter, 3)
      assert function_exported?(NestedFilter, :reject, 2)
      assert function_exported?(NestedFilter, :reject, 3)
    end
  end

  describe "Passbook.Pass.generate_json/1 drop_by APIs" do
    test "drop_by_key/2 still strips nested keys including Jason string __struct__" do
      decoded = %{
        "description" => "Test pass",
        "__struct__" => "Passbook.Pass",
        "generic" => %{
          "__struct__" => "Passbook.PassStructure",
          "primaryFields" => [%{"key" => "name", "value" => "Ada"}]
        }
      }

      assert NestedFilter.drop_by_key(decoded, ["__struct__"]) == %{
               "description" => "Test pass",
               "generic" => %{
                 "primaryFields" => [%{"key" => "name", "value" => "Ada"}]
               }
             }
    end

    test "drop_by_value/2 still strips nils and empty maps the way generate_json/1 does" do
      decoded = %{
        "description" => "Test pass",
        "barcode" => nil,
        "generic" => %{
          "primaryFields" => [%{"key" => "name", "value" => "Ada"}],
          "secondaryFields" => nil,
          "empty" => %{}
        }
      }

      assert NestedFilter.drop_by_value(decoded, [nil, %{}]) == %{
               "description" => "Test pass",
               "generic" => %{
                 "primaryFields" => [%{"key" => "name", "value" => "Ada"}]
               }
             }
    end
  end

  describe "2.2.0 empties option" do
    test "take_by_key/2 still prunes unmatched branches by default" do
      records = %{active: %{id: 1, name: "Ada"}, pending: %{name: "Bo"}}

      assert NestedFilter.take_by_key(records, [:id]) == %{active: %{id: 1}}
    end

    test "take_by_key/3 empties: :keep preserves emptied containers" do
      records = %{active: %{id: 1, name: "Ada"}, pending: %{name: "Bo"}}

      assert NestedFilter.take_by_key(records, [:id], empties: :keep) == %{
               active: %{id: 1},
               pending: %{}
             }
    end

    test "compact/1 still prunes empty containers by default" do
      assert NestedFilter.compact(%{a: 1, b: %{c: nil}, e: %{f: 1, g: nil}}) ==
               %{
                 a: 1,
                 e: %{f: 1}
               }
    end

    test "compact/2 empties: :keep leaves emptied containers" do
      assert NestedFilter.compact(%{a: 1, b: %{c: nil}}, empties: :keep) == %{
               a: 1,
               b: %{}
             }
    end

    test "compact/2 prune_empty: false still aliases empties: :keep" do
      assert NestedFilter.compact(%{a: 1, b: %{c: nil}}, prune_empty: false) ==
               %{
                 a: 1,
                 b: %{}
               }
    end

    test "compact/2 raises when both :empties and :prune_empty are passed" do
      assert_raise ArgumentError,
                   "compact/2 accepts either :empties or the deprecated :prune_empty, not both",
                   fn ->
                     NestedFilter.compact(%{a: 1},
                       empties: :keep,
                       prune_empty: false
                     )
                   end
    end

    test "empties: other than :keep or :prune raises ArgumentError" do
      assert_raise ArgumentError,
                   ~r/expected :empties to be :keep or :prune/,
                   fn ->
                     NestedFilter.compact(%{a: nil}, empties: :drop)
                   end
    end

    test "2.2.0 source defines empties_mode/1 for filter and compact" do
      source = File.read!(@nested_filter)

      assert source =~ "defp empties_mode(opts) do"
      assert source =~ "defp compact_prune_empty?(opts) do"

      assert source =~
               "compact/2 accepts either :empties or the deprecated :prune_empty, not both"
    end
  end
end
