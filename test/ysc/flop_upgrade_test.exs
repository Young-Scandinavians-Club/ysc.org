defmodule Ysc.FlopUpgradeTest do
  @moduledoc """
  Guards the flop 0.28.0 / flop_phoenix 0.26.3 upgrade.

  0.28.0 appends the primary key as a sort tiebreaker, rejects `ecto_type: nil`
  on join fields, and drops `:=~` on booleans. We use page pagination (not
  cursors), declare `ecto_type: :string` on join fields, and do not pass
  `sortable`/`filterable` into `Flop.validate_and_run/3` to add extra fields.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.User
  alias Ysc.Bookings.Booking
  alias Ysc.Events.Event
  alias Ysc.Media.Image
  alias Ysc.Newsletter.Subscriber
  alias Ysc.Posts.Post

  describe "0.28.0 / 0.26.3 Hex locks" do
    test "locks flop to 0.28.0 and flop_phoenix to 0.26.3" do
      assert to_string(Application.spec(:flop, :vsn)) == "0.28.0"
      assert to_string(Application.spec(:flop_phoenix, :vsn)) == "0.26.3"
    end

    test "validate_and_run/3 and run/3 still exist" do
      assert function_exported?(Flop, :validate_and_run, 3)
      assert function_exported?(Flop, :validate, 2)
      assert function_exported?(Flop, :run, 3)
      assert function_exported?(Flop, :ordering, 2)
      assert function_exported?(Flop, :cursor_fields, 2)
    end
  end

  describe "Flop.Schema 0.28 protocol" do
    test "primary_key is the ULID :id on schemas we paginate" do
      assert Flop.Schema.primary_key(%User{}) == [:id]
      assert Flop.Schema.primary_key(%Booking{}) == [:id]
      assert Flop.Schema.primary_key(%Event{}) == [:id]
      assert Flop.Schema.primary_key(%Post{}) == [:id]
      assert Flop.Schema.primary_key(%Subscriber{}) == [:id]
      assert Flop.Schema.primary_key(%Image{}) == [:id]
    end

    test "tiebreaker is unset so Flop defaults to the primary key" do
      assert Flop.Schema.tiebreaker(%User{}) == nil
      assert Flop.Schema.tiebreaker(%Booking{}) == nil
      assert Flop.Schema.max_filters(%User{}) == nil
    end
  end

  describe "ordering/2 primary-key tiebreaker" do
    test "appends :id to the requested order" do
      flop = %Flop{
        order_by: [:first_name, :last_name],
        order_directions: [:asc, :asc]
      }

      assert Flop.ordering(flop, for: User) == [
               asc: :first_name,
               asc: :last_name,
               asc: :id
             ]

      assert Flop.cursor_fields(flop, for: User) == [
               :first_name,
               :last_name,
               :id
             ]
    end

    test "does not duplicate :id when it is already the last order field" do
      flop = %Flop{order_by: [:id], order_directions: [:desc]}
      assert Flop.ordering(flop, for: User) == [desc: :id]
    end

    test "tiebreaker: false restores the previous order list" do
      flop = %Flop{order_by: [:inserted_at], order_directions: [:desc]}

      assert Flop.ordering(flop, for: Booking, tiebreaker: false) == [
               desc: :inserted_at
             ]
    end
  end

  describe "boolean filter operators (0.28.0)" do
    test "still accepts == on Subscriber.subscribed" do
      params = %{
        "filters" => [
          %{"field" => "subscribed", "op" => "==", "value" => "true"}
        ]
      }

      assert {:ok, %Flop{filters: [filter]}} =
               Flop.validate(params, for: Subscriber)

      assert filter.field == :subscribed
      assert filter.op == :==
      assert filter.value == true
    end

    test "rejects :=~ on boolean subscribed" do
      params = %{
        "filters" => [
          %{"field" => "subscribed", "op" => "=~", "value" => "true"}
        ]
      }

      assert {:error, %Flop.Meta{errors: errors}} =
               Flop.validate(params, for: Subscriber)

      assert errors[:filters]
    end
  end

  describe "join field get_field/2 (0.28.0)" do
    test "raises when the association is not loaded" do
      booking = %Booking{}

      assert_raise ArgumentError, ~r/association :user is not loaded/, fn ->
        Flop.Schema.get_field(booking, :user_first)
      end
    end

    test "reads join fields when the association is loaded" do
      booking = %Booking{
        user: %User{
          first_name: "Ada",
          last_name: "Lovelace",
          email: "ada@ysc.org"
        }
      }

      assert Flop.Schema.get_field(booking, :user_first) == "Ada"
      assert Flop.Schema.get_field(booking, :user_last) == "Lovelace"
      assert Flop.Schema.get_field(booking, :user_email) == "ada@ysc.org"
    end
  end

  describe "validate_and_run/3 with the default tiebreaker" do
    test "paginates users without changing requested order_by metadata" do
      user_fixture(%{
        first_name: "Ada",
        last_name: "Byron",
        phone_number: unique_user_phone()
      })

      user_fixture(%{
        first_name: "Ada",
        last_name: "Lovelace",
        phone_number: unique_user_phone()
      })

      params = %{
        page: 1,
        page_size: 10,
        order_by: [:first_name, :last_name],
        order_directions: [:asc, :asc]
      }

      assert {:ok, {users, meta}} =
               Flop.validate_and_run(User, params, for: User)

      assert length(users) >= 2
      assert meta.current_page == 1
      assert meta.flop.order_by == [:first_name, :last_name]
      assert meta.flop.order_directions == [:asc, :asc]

      assert Flop.ordering(meta.flop, for: User) == [
               asc: :first_name,
               asc: :last_name,
               asc: :id
             ]
    end
  end
end
