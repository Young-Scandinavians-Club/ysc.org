defmodule Ysc.FlopCursorSecurityTest do
  use ExUnit.Case, async: true

  alias Flop.Cursor
  alias Ysc.Accounts.User
  alias Ysc.Bookings.Booking
  alias Ysc.Events.Event
  alias Ysc.Posts.Post

  describe "decode/1 cursor hardening (flop 0.26.6+)" do
    test "rejects cursors larger than the default 8 KB limit" do
      oversized = String.duplicate("A", 8_193)

      assert Cursor.decode(oversized) == :error
    end

    test "rejects cursors containing compressed Erlang terms" do
      # 131 = version tag, 80 = zlib-compressed term tag (see Erlang external term format)
      compressed = Base.url_encode64(<<131, 80, 1, 2, 3>>)

      assert Cursor.decode(compressed) == :error
    end

    test "accepts a valid encoded cursor within size limits" do
      cursor = Cursor.encode(%{id: 1})

      assert {:ok, %{id: 1}} = Cursor.decode(cursor)
    end
  end

  describe "max_filters (flop 0.27.0+)" do
    test "rejects more than 20 filters by default" do
      filters =
        Enum.map(1..21, fn i ->
          %{"field" => "email", "op" => "==", "value" => "user#{i}@ysc.org"}
        end)

      assert {:error, %Flop.Meta{errors: errors}} =
               Flop.validate(%{"filters" => filters}, for: User)

      assert {"must have at most %{count} items", opts} =
               List.first(errors[:filters])

      assert opts[:count] == 20
    end

    test "accepts 20 filters" do
      filters =
        Enum.map(1..20, fn i ->
          %{"field" => "email", "op" => "==", "value" => "user#{i}@ysc.org"}
        end)

      assert {:ok, %Flop{filters: validated}} =
               Flop.validate(%{"filters" => filters}, for: User)

      assert length(validated) == 20
    end
  end

  describe "filter value hardening (flop 0.27.1+)" do
    test "rejects filter values containing NUL bytes" do
      params = %{
        "filters" => [
          %{"field" => "email", "op" => "ilike", "value" => "foo\0bar"}
        ]
      }

      assert {:error, %Flop.Meta{errors: errors}} =
               Flop.validate(params, for: User)

      assert invalid_filter_value?(errors)
    end

    test "rejects filter values with invalid UTF-8" do
      params = %{
        "filters" => [
          %{"field" => "email", "op" => "ilike", "value" => <<0xFF>>}
        ]
      }

      assert {:error, %Flop.Meta{errors: errors}} =
               Flop.validate(params, for: User)

      assert invalid_filter_value?(errors)
    end
  end

  describe "join field ecto_type (flop 0.27.0+)" do
    test "Event organizer join fields declare ecto_type" do
      assert Flop.Schema.field_info(%Event{}, :organizer_first).ecto_type ==
               :string

      assert Flop.Schema.field_info(%Event{}, :organizer_last).ecto_type ==
               :string
    end

    test "Post author join fields declare ecto_type" do
      assert Flop.Schema.field_info(%Post{}, :author_first).ecto_type == :string
      assert Flop.Schema.field_info(%Post{}, :author_last).ecto_type == :string
    end

    test "Booking user join fields declare ecto_type" do
      assert Flop.Schema.field_info(%Booking{}, :user_first).ecto_type ==
               :string

      assert Flop.Schema.field_info(%Booking{}, :user_email).ecto_type ==
               :string
    end
  end

  describe "UnknownFieldError (flop 0.27.0+)" do
    test "raises for fields that are not configured on the schema" do
      assert_raise Flop.UnknownFieldError, fn ->
        Flop.Schema.field_info(%User{}, :not_a_real_field)
      end
    end
  end

  defp invalid_filter_value?(errors) do
    errors
    |> Keyword.get(:filters, [])
    |> List.wrap()
    |> List.flatten()
    |> Enum.any?(fn
      {:value, [{"is invalid", _} | _]} -> true
      %{value: [{"is invalid", _} | _]} -> true
      other -> match?({_, [{"is invalid", _} | _]}, other)
    end)
  end
end
