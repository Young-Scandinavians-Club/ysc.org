defmodule Ysc.FlopUpgradeTest do
  @moduledoc """
  Guards the flop 0.29.1 / flop_phoenix 0.27.0 upgrade.

  0.29.0 turns `Flop.Schema` from a protocol into a behaviour (`use Flop.Schema`
  + `@flop_options`). `field_info/2`, `get_field/3`, and `primary_key/1` take
  the schema module. Schema option accessors are gone; use `Flop.get_option/3`
  and `Flop.allowed_fields/2`. We use page pagination (not cursors), declare
  `ecto_type: :string` on join fields, and do not pass `sortable`/`filterable`
  into `Flop.validate_and_run/3` to add extra fields.

  0.29.1 is a patch. InvalidParamsError / InvalidCursorError messages omit raw
  params and cursors (the exception fields still hold them). `get_field/3` on a
  plain map without the join path's first key falls back to the field name.
  Non-struct `Flop.Schema` + Ecto adapter raises. `max_cursor_size` applies to
  unvalidated cursors. We do not use cursor pagination or non-struct schemas.
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

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/flop/CHANGELOG.md", __DIR__)
  @errors_src Path.expand("../../deps/flop/lib/flop/errors.ex", __DIR__)
  @ecto_adapter_src Path.expand(
                      "../../deps/flop/lib/flop/adapter/ecto.ex",
                      __DIR__
                    )

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

  setup_all do
    {:ok, _} = Application.ensure_all_started(:flop)
    {:module, Flop} = Code.ensure_loaded(Flop)
    {:module, Flop.Schema} = Code.ensure_loaded(Flop.Schema)
    {:module, Flop.Cursor} = Code.ensure_loaded(Flop.Cursor)

    {:module, Flop.InvalidParamsError} =
      Code.ensure_loaded(Flop.InvalidParamsError)

    {:module, Flop.InvalidCursorError} =
      Code.ensure_loaded(Flop.InvalidCursorError)

    :ok
  end

  describe "0.29.1 / 0.27.0 Hex locks" do
    test "locks flop to 0.29.1 and flop_phoenix to 0.27.0" do
      assert to_string(Application.spec(:flop, :vsn)) == "0.29.1"
      assert to_string(Application.spec(:flop_phoenix, :vsn)) == "0.27.0"
    end

    test "mix.exs pins the 0.29.1 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:flop, "~> 0.29.1"}|
    end

    test "companion lock is 0.29.1" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"flop": {:hex, :flop, "0.29.1"|
      refute lock =~ ~s|"flop": {:hex, :flop, "0.29.0"|
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
      {:module, Flop.Schema} = Code.ensure_loaded(Flop.Schema)
      assert function_exported?(Flop.Schema, :flop_schema!, 1)
      {:module, Flop.Cursor} = Code.ensure_loaded(Flop.Cursor)
      assert function_exported?(Flop.Cursor, :decode, 2)
      assert function_exported?(Flop.Cursor, :decode!, 2)
    end
  end

  describe "0.29.1 changelog" do
    test "documents the param-redaction security fix and get_field fallback" do
      changelog = File.read!(@changelog)

      v0291 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[0.29.1]"))

      assert v0291
      refute v0291 =~ "Breaking"

      assert v0291 =~
               "Leave the parameter values out of the `Flop.InvalidParamsError` message"

      assert v0291 =~ "the cursor out of the `Flop.InvalidCursorError` message"

      assert v0291 =~
               "Fall back to the field name when a cursor or `Flop.Schema.get_field/3`"

      assert v0291 =~
               "Raise an `ArgumentError` when a module without a struct uses `Flop.Schema`"

      assert v0291 =~
               "Apply `max_cursor_size` from function options and backend modules"
    end
  end

  describe "0.29.1 exception messages omit raw params and cursors" do
    test "InvalidParamsError message leaves values in the params field" do
      secret = "secret-pii-should-not-leak@ysc.org"

      params = %{
        "page" => "not-a-page",
        "filters" => [
          %{"field" => "email", "op" => "==", "value" => secret}
        ]
      }

      error =
        assert_raise Flop.InvalidParamsError, fn ->
          Flop.validate!(params, for: User)
        end

      message = Exception.message(error)

      assert message =~ "invalid Flop parameters"
      assert message =~ "The parameter values are left out of this message"
      refute message =~ secret
      assert error.params["filters"]
      assert hd(error.params["filters"])["value"] == secret
    end

    test "InvalidCursorError message leaves the cursor in the cursor field" do
      cursor = "not-a-valid-cursor-payload"

      error =
        assert_raise Flop.InvalidCursorError, fn ->
          Flop.Cursor.decode!(cursor)
        end

      message = Exception.message(error)

      assert message =~ "invalid cursor"
      assert message =~ "The cursor is left out of this message"
      refute message =~ cursor
      assert error.cursor == cursor
    end

    test "errors.ex still documents the redaction" do
      source = File.read!(@errors_src)

      assert source =~ "The parameter values are left out of this message"
      assert source =~ "The cursor is left out of this message"
    end
  end

  describe "0.29.1 join-field get_field/3 map fallback" do
    test "reads a join field from a flat map keyed by the field name" do
      assert Flop.Schema.get_field(Booking, %{user_first: "Ada"}, :user_first) ==
               "Ada"

      assert Flop.Schema.get_field(
               Booking,
               %{user_last: "Lovelace", user_email: "ada@ysc.org"},
               :user_email
             ) == "ada@ysc.org"
    end

    test "still walks the nested join path when the first key is present" do
      item = %{user: %{first_name: "Ada", last_name: "Lovelace"}}

      assert Flop.Schema.get_field(Booking, item, :user_first) == "Ada"
      assert Flop.Schema.get_field(Booking, item, :user_last) == "Lovelace"
    end

    test "ecto adapter still raises for a non-struct Flop.Schema module" do
      source = File.read!(@ecto_adapter_src)

      assert source =~ "schema module is not an Ecto schema"

      assert source =~
               "def init_schema_opts(_opts, _schema_opts, caller_module, nil)"
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
