defmodule Ysc.Forms.VolunteerTest do
  @moduledoc """
  Tests for Volunteer form schema.

  These tests verify:
  - Required field validation (email, name)
  - Email format validation
  - Interest field handling (all optional booleans)
  - User association
  - Database operations
  """
  use Ysc.DataCase, async: true

  alias Ysc.Forms.Volunteer
  alias Ysc.Repo

  import Ysc.AccountsFixtures

  describe "changeset/2" do
    test "creates valid changeset with required fields" do
      attrs = %{
        email: "volunteer@example.com",
        name: "Jane Doe"
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      assert changeset.valid?
      assert changeset.changes.email == "volunteer@example.com"
      assert changeset.changes.name == "Jane Doe"
    end

    test "creates valid changeset with all fields" do
      user = user_fixture()

      attrs = %{
        email: "volunteer@example.com",
        name: "Jane Doe",
        interest_events: true,
        interest_activities: true,
        interest_clear_lake: false,
        interest_tahoe: true,
        interest_marketing: false,
        interest_website: true,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      assert changeset.valid?
      assert changeset.changes.email == "volunteer@example.com"
      assert changeset.changes.name == "Jane Doe"
      assert changeset.changes.interest_events == true
      assert changeset.changes.interest_activities == true
      assert changeset.changes.interest_clear_lake == false
      assert changeset.changes.interest_tahoe == true
      assert changeset.changes.interest_marketing == false
      assert changeset.changes.interest_website == true
      assert changeset.changes.user_id == user.id
    end

    test "requires email" do
      attrs = %{
        name: "Jane Doe"
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "requires name" do
      attrs = %{
        email: "volunteer@example.com"
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "validates email format" do
      attrs = %{
        email: "invalid-email",
        name: "Jane Doe"
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).email
    end

    test "accepts valid email formats" do
      valid_emails = [
        "simple@example.com",
        "user.name@example.com",
        "user+tag@example.com",
        "user_name@example.co.uk",
        "123@example.com"
      ]

      for email <- valid_emails do
        attrs = %{
          email: email,
          name: "Jane Doe"
        }

        changeset = Volunteer.changeset(%Volunteer{}, attrs)

        assert changeset.valid?, "Expected #{email} to be valid"
      end
    end

    test "allows all interest fields to be nil" do
      attrs = %{
        email: "volunteer@example.com",
        name: "Jane Doe",
        interest_events: nil,
        interest_activities: nil,
        interest_clear_lake: nil,
        interest_tahoe: nil,
        interest_marketing: nil,
        interest_website: nil
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      assert changeset.valid?
    end

    test "allows all interest fields to be false" do
      attrs = %{
        email: "volunteer@example.com",
        name: "Jane Doe",
        interest_events: false,
        interest_activities: false,
        interest_clear_lake: false,
        interest_tahoe: false,
        interest_marketing: false,
        interest_website: false
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      assert changeset.valid?
    end

    test "allows all interest fields to be true" do
      attrs = %{
        email: "volunteer@example.com",
        name: "Jane Doe",
        interest_events: true,
        interest_activities: true,
        interest_clear_lake: true,
        interest_tahoe: true,
        interest_marketing: true,
        interest_website: true
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      assert changeset.valid?
    end

    test "allows user_id to be nil (anonymous volunteer)" do
      attrs = %{
        email: "anonymous@example.com",
        name: "Anonymous Volunteer",
        user_id: nil
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      assert changeset.valid?
    end
  end

  describe "database operations" do
    test "can insert and retrieve volunteer signup" do
      user = user_fixture()

      attrs = %{
        email: "test@example.com",
        name: "Test Volunteer",
        interest_events: true,
        interest_activities: false,
        interest_clear_lake: true,
        interest_tahoe: false,
        interest_marketing: true,
        interest_website: false,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)
      {:ok, volunteer} = Repo.insert(changeset)

      retrieved = Repo.get(Volunteer, volunteer.id)

      assert retrieved.email == "test@example.com"
      assert retrieved.name == "Test Volunteer"
      assert retrieved.interest_events == true
      assert retrieved.interest_activities == false
      assert retrieved.interest_clear_lake == true
      assert retrieved.interest_tahoe == false
      assert retrieved.interest_marketing == true
      assert retrieved.interest_website == false
      assert retrieved.user_id == user.id
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can insert volunteer with minimal data" do
      attrs = %{
        email: "minimal@example.com",
        name: "Minimal Volunteer"
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)
      {:ok, volunteer} = Repo.insert(changeset)

      retrieved = Repo.get(Volunteer, volunteer.id)

      assert retrieved.email == "minimal@example.com"
      assert retrieved.name == "Minimal Volunteer"
      # Boolean fields default to false in the database
      assert retrieved.interest_events == false
      assert retrieved.interest_activities == false
      assert retrieved.interest_clear_lake == false
      assert retrieved.interest_tahoe == false
      assert retrieved.interest_marketing == false
      assert retrieved.interest_website == false
      assert retrieved.user_id == nil
    end

    test "can update volunteer interests" do
      attrs = %{
        email: "update@example.com",
        name: "Update Test",
        interest_events: false
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)
      {:ok, volunteer} = Repo.insert(changeset)

      # Update interests
      update_attrs = %{
        interest_events: true,
        interest_marketing: true
      }

      update_changeset = Volunteer.changeset(volunteer, update_attrs)
      {:ok, updated} = Repo.update(update_changeset)

      assert updated.interest_events == true
      assert updated.interest_marketing == true
    end

    test "allows multiple volunteers with same email" do
      # No unique constraint on email
      attrs1 = %{
        email: "same@example.com",
        name: "First Volunteer"
      }

      attrs2 = %{
        email: "same@example.com",
        name: "Second Volunteer"
      }

      changeset1 = Volunteer.changeset(%Volunteer{}, attrs1)
      {:ok, _volunteer1} = Repo.insert(changeset1)

      changeset2 = Volunteer.changeset(%Volunteer{}, attrs2)
      {:ok, _volunteer2} = Repo.insert(changeset2)

      # Both should succeed
      volunteers =
        Repo.all(from v in Volunteer, where: v.email == "same@example.com")

      assert length(volunteers) == 2
    end
  end
end
