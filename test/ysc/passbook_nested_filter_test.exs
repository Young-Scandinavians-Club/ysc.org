defmodule Ysc.PassbookNestedFilterTest do
  use ExUnit.Case, async: true

  alias Passbook.LowerLevel.Field
  alias Passbook.Pass
  alias Passbook.PassStructure

  test "generate_json/1 strips struct keys, nil values, and empty maps with nested_filter 2.x" do
    pass = %Pass{
      description: "Test pass",
      organization_name: "YSC",
      pass_type_identifier: "pass.org.ysc.test",
      serial_number: "serial-1",
      team_identifier: "TEAM123",
      generic: %PassStructure{
        primary_fields: [
          %Field{key: "name", label: "Name", value: "Ada"}
        ],
        secondary_fields: nil
      },
      barcode: nil
    }

    json = Pass.generate_json(pass)
    decoded = Jason.decode!(json)

    refute Map.has_key?(decoded, "__struct__")
    refute has_key_anywhere?(decoded, "__struct__")
    refute has_value_anywhere?(decoded, nil)
    refute has_empty_map_anywhere?(decoded)
    assert decoded["description"] == "Test pass"

    assert get_in(decoded, ["generic", "primaryFields", Access.at(0), "value"]) ==
             "Ada"
  end

  defp has_key_anywhere?(term, key) when is_map(term) do
    Enum.any?(term, fn
      {^key, _} -> true
      {_, value} -> has_key_anywhere?(value, key)
    end)
  end

  defp has_key_anywhere?(term, key) when is_list(term) do
    Enum.any?(term, &has_key_anywhere?(&1, key))
  end

  defp has_key_anywhere?(_term, _key), do: false

  defp has_value_anywhere?(term, value) when is_map(term) do
    Enum.any?(term, fn
      {_, ^value} -> true
      {_, nested} -> has_value_anywhere?(nested, value)
    end)
  end

  defp has_value_anywhere?(term, value) when is_list(term) do
    Enum.any?(term, &has_value_anywhere?(&1, value))
  end

  defp has_value_anywhere?(_term, _value), do: false

  defp has_empty_map_anywhere?(term) when is_map(term) do
    term == %{} or
      Enum.any?(term, fn {_, value} -> has_empty_map_anywhere?(value) end)
  end

  defp has_empty_map_anywhere?(term) when is_list(term) do
    Enum.any?(term, &has_empty_map_anywhere?/1)
  end

  defp has_empty_map_anywhere?(_term), do: false
end
