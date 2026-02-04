defmodule Ysc.Accounts.AddressTest do
  use Ysc.DataCase, async: true

  alias Ysc.Accounts.Address

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{
        address: "123 Main St",
        city: "San Francisco",
        postal_code: "94102",
        country: "United States"
      }

      changeset = Address.changeset(%Address{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with optional region field" do
      attrs = %{
        address: "456 Oak Ave",
        city: "Portland",
        region: "Oregon",
        postal_code: "97201",
        country: "United States"
      }

      changeset = Address.changeset(%Address{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with user_id" do
      attrs = %{
        address: "789 Pine St",
        city: "Seattle",
        postal_code: "98101",
        country: "United States",
        user_id: Ecto.ULID.generate()
      }

      changeset = Address.changeset(%Address{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset when missing address" do
      attrs = %{
        city: "Boston",
        postal_code: "02101",
        country: "United States"
      }

      changeset = Address.changeset(%Address{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).address
    end

    test "invalid changeset when missing city" do
      attrs = %{
        address: "123 Main St",
        postal_code: "10001",
        country: "United States"
      }

      changeset = Address.changeset(%Address{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).city
    end

    test "invalid changeset when missing postal_code" do
      attrs = %{
        address: "123 Main St",
        city: "New York",
        country: "United States"
      }

      changeset = Address.changeset(%Address{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).postal_code
    end

    test "invalid changeset when missing country" do
      attrs = %{
        address: "123 Main St",
        city: "Chicago",
        postal_code: "60601"
      }

      changeset = Address.changeset(%Address{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).country
    end

    test "invalid changeset when address exceeds max length" do
      attrs = %{
        address: String.duplicate("a", 256),
        city: "Austin",
        postal_code: "78701",
        country: "United States"
      }

      changeset = Address.changeset(%Address{}, attrs)
      refute changeset.valid?

      assert "should be at most 255 character(s)" in errors_on(changeset).address
    end

    test "valid changeset when address is at max length" do
      attrs = %{
        address: String.duplicate("a", 255),
        city: "Austin",
        postal_code: "78701",
        country: "United States"
      }

      changeset = Address.changeset(%Address{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset when city exceeds max length" do
      attrs = %{
        address: "123 Main St",
        city: String.duplicate("a", 101),
        postal_code: "12345",
        country: "United States"
      }

      changeset = Address.changeset(%Address{}, attrs)
      refute changeset.valid?
      assert "should be at most 100 character(s)" in errors_on(changeset).city
    end

    test "invalid changeset when region exceeds max length" do
      attrs = %{
        address: "123 Main St",
        city: "Denver",
        region: String.duplicate("a", 101),
        postal_code: "80201",
        country: "United States"
      }

      changeset = Address.changeset(%Address{}, attrs)
      refute changeset.valid?
      assert "should be at most 100 character(s)" in errors_on(changeset).region
    end

    test "invalid changeset when postal_code exceeds max length" do
      attrs = %{
        address: "123 Main St",
        city: "Miami",
        postal_code: String.duplicate("1", 21),
        country: "United States"
      }

      changeset = Address.changeset(%Address{}, attrs)
      refute changeset.valid?

      assert "should be at most 20 character(s)" in errors_on(changeset).postal_code
    end

    test "invalid changeset when country exceeds max length" do
      attrs = %{
        address: "123 Main St",
        city: "Phoenix",
        postal_code: "85001",
        country: String.duplicate("a", 101)
      }

      changeset = Address.changeset(%Address{}, attrs)
      refute changeset.valid?

      assert "should be at most 100 character(s)" in errors_on(changeset).country
    end

    test "valid changeset with international address" do
      attrs = %{
        address: "10 Downing Street",
        city: "London",
        postal_code: "SW1A 2AA",
        country: "United Kingdom"
      }

      changeset = Address.changeset(%Address{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset allows region to be nil" do
      attrs = %{
        address: "123 Main St",
        city: "Paris",
        postal_code: "75001",
        country: "France",
        region: nil
      }

      changeset = Address.changeset(%Address{}, attrs)
      assert changeset.valid?
    end
  end

  describe "from_signup_application_changeset/2" do
    test "creates valid changeset from signup application data" do
      signup_application = %{
        address: "789 Elm St",
        city: "Los Angeles",
        region: "California",
        postal_code: "90001",
        country: "United States"
      }

      changeset =
        Address.from_signup_application_changeset(
          %Address{},
          signup_application
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :address) == "789 Elm St"
      assert Ecto.Changeset.get_change(changeset, :city) == "Los Angeles"
      assert Ecto.Changeset.get_change(changeset, :region) == "California"
      assert Ecto.Changeset.get_change(changeset, :postal_code) == "90001"
      assert Ecto.Changeset.get_change(changeset, :country) == "United States"
    end

    test "creates changeset without region from signup application" do
      signup_application = %{
        address: "321 Birch Rd",
        city: "Vancouver",
        region: nil,
        postal_code: "V6B 1A1",
        country: "Canada"
      }

      changeset =
        Address.from_signup_application_changeset(
          %Address{},
          signup_application
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :region) == nil
    end

    test "creates invalid changeset when signup application is missing required fields" do
      signup_application = %{
        address: "456 Maple Dr",
        city: nil,
        region: "Texas",
        postal_code: "75001",
        country: "United States"
      }

      changeset =
        Address.from_signup_application_changeset(
          %Address{},
          signup_application
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).city
    end

    test "preserves validation errors from signup application data" do
      signup_application = %{
        address: String.duplicate("a", 256),
        city: "Houston",
        region: "Texas",
        postal_code: "77001",
        country: "United States"
      }

      changeset =
        Address.from_signup_application_changeset(
          %Address{},
          signup_application
        )

      refute changeset.valid?

      assert "should be at most 255 character(s)" in errors_on(changeset).address
    end
  end
end
