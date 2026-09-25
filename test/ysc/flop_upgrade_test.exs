defmodule Ysc.FlopUpgradeTest do
  @moduledoc """
  Guards the flop 0.29.0 / flop_phoenix 0.27.0 upgrade.

  0.29.0 turns `Flop.Schema` from a protocol into a behaviour (`use Flop.Schema`
  + `@flop_options`). `field_info/2`, `get_field/3`, and `primary_key/1` take
  the schema module. Schema option accessors are gone; use `Flop.get_option/3`
  and `Flop.allowed_fields/2`. We use page pagination (not cursors), declare
  `ecto_type: :string` on join fields, and do not pass `sortable`/`filterable`
  into `Flop.validate_and_run/3` to add extra fields.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.User
  alias Ysc.Bookings.Booking
  alias Ysc.Events.Event
  alias Ysc.Media.Image
  alias Ysc.Newsletter.Edition
  alias Ysc.Newsletter.Subscriber
  alias Ysc.Posts.Post
  alias Ysc.Tickets.TicketOrder

  @paginated_schemas [
    User,
    Booking,
    Event,
    Post,
    Subscriber,
    Image,
    Edition,
    TicketOrder
  ]

  describe "0.29.0 / 0.27.0 Hex locks" do
    test "locks flop to 0.29.0 and flop_phoenix to 0.27.0" do
      assert to_string(Application.spec(:flop, :vsn)) == "0.29.0"
      assert to_string(Application.spec(:flop_phoenix, :vsn)) == "0.27.0"
    end

    test "validate_and_run/3 and run/3 still exist" do
      assert {:module, _} = Code.ensure_loaded(Flop)
      assert function_exported?(Flop, :validate_and_run, 3)
      assert function_exported?(Flop, :validate, 2)
      assert function_exported?(Flop, :run, 3)
      assert function_exported?(Flop, :ordering, 2)
      assert function_exported?(Flop, :cursor_fields, 2)
      assert function_exported?(Flop, :allowed_fields, 2)
      assert function_exported?(Flop, :get_option, 3)
      assert {:module, _} = Code.ensure_loaded(Flop.Schema)
      assert function_exported?(Flop.Schema, :flop_schema!, 1)
    end
  end

  describe "Flop.Schema 0.29 behaviour" do
    test "schemas we paginate implement the behaviour via __flop_schema__/0" do
      for schema <- @paginated_schemas do
        assert {:module, _} = Code.ensure_loaded(schema)
        assert function_exported?(schema, :__flop_schema__, 0)
        config = Flop.Schema.flop_schema!(schema)
        assert is_map(config)
        assert is_list(config.filterable)
        assert is_list(config.sortable)
      end
    end

    test "primary_key is the ULID :id on schemas we paginate" do
      for schema <- @paginated_schemas do
        assert Flop.Schema.primary_key(schema) == [:id]
      end
    end

    test "unset tiebreaker and max_filters stay nil on the schema config" do
      user_config = Flop.Schema.flop_schema!(User)
      booking_config = Flop.Schema.flop_schema!(Booking)

      assert user_config.tiebreaker == nil
      assert booking_config.tiebreaker == nil
      assert user_config.max_filters == nil
    end
  end

  describe "allowed_fields/2 and get_option/3" do
    test "returns the schema filterable and sortable fields" do
      assert Flop.allowed_fields(:filterable, for: Image) == [
               :title,
               :alt_text,
               :user_id
             ]

      assert Flop.allowed_fields(:sortable, for: Image) == [:inserted_at]
    end

    test "narrows sortable fields when a query option is passed" do
      assert Flop.allowed_fields(:sortable,
               for: Image,
               sortable: [:inserted_at]
             ) ==
               [:inserted_at]

      assert Flop.allowed_fields(:filterable, for: Image, filterable: [:title]) ==
               [:title]
    end

    test "reads default_limit and max_limit from the schema" do
      assert Flop.get_option(:default_limit, for: User) == 50
      assert Flop.get_option(:max_limit, for: User) == 200
      assert Flop.get_option(:default_limit, for: Subscriber) == 20
      assert Flop.get_option(:max_limit, for: Subscriber) == 100
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

  describe "join field get_field/3 (0.29.0)" do
    test "raises when the association is not loaded" do
      booking = %Booking{}

      assert_raise ArgumentError, ~r/association :user is not loaded/, fn ->
        Flop.Schema.get_field(Booking, booking, :user_first)
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

      assert Flop.Schema.get_field(Booking, booking, :user_first) == "Ada"
      assert Flop.Schema.get_field(Booking, booking, :user_last) == "Lovelace"

      assert Flop.Schema.get_field(Booking, booking, :user_email) ==
               "ada@ysc.org"
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
