defmodule Ysc.Accounts.SignupApplicationTest do
  @moduledoc """
  Tests for SignupApplication schema.

  These tests verify:
  - Required field validation
  - Membership eligibility validation
  - Agreed to bylaws validation
  - Review outcome changeset
  - Field validations (strings, dates, booleans)
  - Membership type validation
  """
  use Ysc.DataCase, async: true

  alias Ysc.Accounts.SignupApplication
  alias Ysc.Repo

  import Ysc.AccountsFixtures

  describe "application_changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        birth_date: ~D[1990-01-01],
        address: "123 Viking Way",
        country: "USA",
        city: "San Francisco",
        postal_code: "94107",
        place_of_birth: "Oslo",
        citizenship: "Norwegian",
        most_connected_nordic_country: "Norway",
        agreed_to_bylaws: true
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      assert changeset.changes.membership_type == :single
      assert changeset.changes.membership_eligibility == [:born_in_scandinavia]
      assert changeset.changes.birth_date == ~D[1990-01-01]
      assert changeset.changes.address == "123 Viking Way"
      assert changeset.changes.country == "USA"
      assert changeset.changes.city == "San Francisco"
      assert changeset.changes.postal_code == "94107"
      assert changeset.changes.place_of_birth == "Oslo"
      assert changeset.changes.citizenship == "Norwegian"
      assert changeset.changes.most_connected_nordic_country == "Norway"
    end

    test "creates valid changeset with optional fields" do
      attrs = %{
        membership_type: "family",
        membership_eligibility: [
          "citizen_of_scandinavia",
          "speak_scandinavian_language"
        ],
        birth_date: ~D[1985-06-15],
        address: "456 Nordic Street",
        country: "USA",
        city: "Seattle",
        region: "WA",
        postal_code: "98101",
        place_of_birth: "Stockholm",
        citizenship: "Swedish",
        most_connected_nordic_country: "Sweden",
        occupation: "Engineer",
        link_to_scandinavia: "Grandparents from Sweden",
        lived_in_scandinavia: "Yes, for 2 years",
        spoken_languages: "Swedish, English",
        hear_about_the_club: "Friend recommendation",
        agreed_to_bylaws: true,
        started: ~U[2024-01-01 10:00:00Z],
        completed: ~U[2024-01-01 11:00:00Z],
        browser_timezone: "America/Los_Angeles"
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      assert changeset.changes.membership_type == :family
      assert changeset.changes.occupation == "Engineer"
      assert changeset.changes.region == "WA"
      assert changeset.changes.link_to_scandinavia == "Grandparents from Sweden"
      assert changeset.changes.lived_in_scandinavia == "Yes, for 2 years"
      assert changeset.changes.spoken_languages == "Swedish, English"
      assert changeset.changes.hear_about_the_club == "Friend recommendation"
      assert changeset.changes.started == ~U[2024-01-01 10:00:00Z]
      assert changeset.changes.completed == ~U[2024-01-01 11:00:00Z]
      assert changeset.changes.browser_timezone == "America/Los_Angeles"
    end

    test "requires membership_type" do
      attrs = %{
        membership_eligibility: ["born_in_scandinavia"],
        birth_date: ~D[1990-01-01],
        address: "123 Viking Way",
        country: "USA",
        city: "San Francisco",
        postal_code: "94107",
        place_of_birth: "Oslo",
        citizenship: "Norwegian",
        most_connected_nordic_country: "Norway",
        agreed_to_bylaws: true
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).membership_type
    end

    test "requires birth_date" do
      attrs = %{
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        address: "123 Viking Way",
        country: "USA",
        city: "San Francisco",
        postal_code: "94107",
        place_of_birth: "Oslo",
        citizenship: "Norwegian",
        most_connected_nordic_country: "Norway",
        agreed_to_bylaws: true
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).birth_date
    end

    test "requires address" do
      attrs = %{
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        birth_date: ~D[1990-01-01],
        country: "USA",
        city: "San Francisco",
        postal_code: "94107",
        place_of_birth: "Oslo",
        citizenship: "Norwegian",
        most_connected_nordic_country: "Norway",
        agreed_to_bylaws: true
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).address
    end

    test "requires country" do
      attrs = %{
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        birth_date: ~D[1990-01-01],
        address: "123 Viking Way",
        city: "San Francisco",
        postal_code: "94107",
        place_of_birth: "Oslo",
        citizenship: "Norwegian",
        most_connected_nordic_country: "Norway",
        agreed_to_bylaws: true
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).country
    end

    test "requires city" do
      attrs = %{
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        birth_date: ~D[1990-01-01],
        address: "123 Viking Way",
        country: "USA",
        postal_code: "94107",
        place_of_birth: "Oslo",
        citizenship: "Norwegian",
        most_connected_nordic_country: "Norway",
        agreed_to_bylaws: true
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).city
    end

    test "requires postal_code" do
      attrs = %{
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        birth_date: ~D[1990-01-01],
        address: "123 Viking Way",
        country: "USA",
        city: "San Francisco",
        place_of_birth: "Oslo",
        citizenship: "Norwegian",
        most_connected_nordic_country: "Norway",
        agreed_to_bylaws: true
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).postal_code
    end

    test "requires place_of_birth" do
      attrs = %{
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        birth_date: ~D[1990-01-01],
        address: "123 Viking Way",
        country: "USA",
        city: "San Francisco",
        postal_code: "94107",
        citizenship: "Norwegian",
        most_connected_nordic_country: "Norway",
        agreed_to_bylaws: true
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).place_of_birth
    end

    test "requires citizenship" do
      attrs = %{
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        birth_date: ~D[1990-01-01],
        address: "123 Viking Way",
        country: "USA",
        city: "San Francisco",
        postal_code: "94107",
        place_of_birth: "Oslo",
        most_connected_nordic_country: "Norway",
        agreed_to_bylaws: true
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).citizenship
    end

    test "requires most_connected_nordic_country" do
      attrs = %{
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        birth_date: ~D[1990-01-01],
        address: "123 Viking Way",
        country: "USA",
        city: "San Francisco",
        postal_code: "94107",
        place_of_birth: "Oslo",
        citizenship: "Norwegian",
        agreed_to_bylaws: true
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?

      assert "can't be blank" in errors_on(changeset).most_connected_nordic_country
    end
  end

  describe "membership_type validation" do
    test "accepts single membership type" do
      attrs = valid_application_attrs(%{membership_type: "single"})

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      assert changeset.changes.membership_type == :single
    end

    test "accepts family membership type" do
      attrs = valid_application_attrs(%{membership_type: "family"})

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      assert changeset.changes.membership_type == :family
    end

    test "rejects invalid membership type" do
      attrs = valid_application_attrs(%{membership_type: "invalid_type"})

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:membership_type] != nil
    end
  end

  describe "agreed_to_bylaws validation" do
    test "requires agreed_to_bylaws to be true" do
      attrs = valid_application_attrs(%{agreed_to_bylaws: true})

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
    end

    test "rejects agreed_to_bylaws = false" do
      attrs = valid_application_attrs(%{agreed_to_bylaws: false})

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "must be accepted" in errors_on(changeset).agreed_to_bylaws
    end

    test "rejects missing agreed_to_bylaws" do
      attrs = valid_application_attrs() |> Map.delete(:agreed_to_bylaws)

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "must be accepted" in errors_on(changeset).agreed_to_bylaws
    end

    test "rejects agreed_to_bylaws = nil" do
      attrs = valid_application_attrs(%{agreed_to_bylaws: nil})

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "must be accepted" in errors_on(changeset).agreed_to_bylaws
    end
  end

  describe "membership_eligibility validation" do
    test "accepts valid citizen_of_scandinavia eligibility" do
      attrs =
        valid_application_attrs(%{
          membership_eligibility: ["citizen_of_scandinavia"]
        })

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?

      assert changeset.changes.membership_eligibility == [
               :citizen_of_scandinavia
             ]
    end

    test "accepts valid born_in_scandinavia eligibility" do
      attrs =
        valid_application_attrs(%{
          membership_eligibility: ["born_in_scandinavia"]
        })

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      assert changeset.changes.membership_eligibility == [:born_in_scandinavia]
    end

    test "accepts valid scandinavian_parent eligibility" do
      attrs =
        valid_application_attrs(%{
          membership_eligibility: ["scandinavian_parent"]
        })

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      assert changeset.changes.membership_eligibility == [:scandinavian_parent]
    end

    test "accepts valid lived_in_scandinavia eligibility" do
      attrs =
        valid_application_attrs(%{
          membership_eligibility: ["lived_in_scandinavia"]
        })

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      assert changeset.changes.membership_eligibility == [:lived_in_scandinavia]
    end

    test "accepts valid speak_scandinavian_language eligibility" do
      attrs =
        valid_application_attrs(%{
          membership_eligibility: ["speak_scandinavian_language"]
        })

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?

      assert changeset.changes.membership_eligibility == [
               :speak_scandinavian_language
             ]
    end

    test "accepts valid spouse_of_member eligibility" do
      attrs =
        valid_application_attrs(%{membership_eligibility: ["spouse_of_member"]})

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      assert changeset.changes.membership_eligibility == [:spouse_of_member]
    end

    test "accepts multiple valid eligibility options" do
      attrs =
        valid_application_attrs(%{
          membership_eligibility: [
            "citizen_of_scandinavia",
            "speak_scandinavian_language",
            "born_in_scandinavia"
          ]
        })

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?

      # Note: clean_and_validate_array sorts the array
      assert changeset.changes.membership_eligibility == [
               :born_in_scandinavia,
               :citizen_of_scandinavia,
               :speak_scandinavian_language
             ]
    end

    test "empty membership_eligibility array is valid and not tracked as a change" do
      # When an empty array is provided, it matches the default value ([])
      # so Ecto doesn't track it as a change
      attrs = valid_application_attrs(%{membership_eligibility: []})

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      # Empty array matches default, so it's valid and not in changes
      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :membership_eligibility)
    end

    test "rejects invalid eligibility option" do
      attrs =
        valid_application_attrs(%{membership_eligibility: ["invalid_option"]})

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:membership_eligibility] != nil
    end

    test "rejects mixed valid and invalid options" do
      attrs =
        valid_application_attrs(%{
          membership_eligibility: ["citizen_of_scandinavia", "invalid_option"]
        })

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      # The EctoEnum cast fails for invalid values and returns "is invalid" error
      refute changeset.valid?
      assert changeset.errors[:membership_eligibility] != nil
      {message, _} = changeset.errors[:membership_eligibility]
      assert message == "is invalid"
    end
  end

  describe "review_outcome_changeset/2" do
    test "creates valid review changeset with all required fields" do
      user = user_fixture()

      attrs = %{
        reviewed_at: ~U[2024-01-15 12:00:00Z],
        review_outcome: "approved",
        reviewed_by_user_id: user.id
      }

      changeset =
        SignupApplication.review_outcome_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      assert changeset.changes.reviewed_at == ~U[2024-01-15 12:00:00Z]
      assert changeset.changes.review_outcome == :approved
      assert changeset.changes.reviewed_by_user_id == user.id
    end

    test "accepts approved review outcome" do
      user = user_fixture()

      attrs = %{
        reviewed_at: ~U[2024-01-15 12:00:00Z],
        review_outcome: "approved",
        reviewed_by_user_id: user.id
      }

      changeset =
        SignupApplication.review_outcome_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      assert changeset.changes.review_outcome == :approved
    end

    test "accepts rejected review outcome" do
      user = user_fixture()

      attrs = %{
        reviewed_at: ~U[2024-01-15 12:00:00Z],
        review_outcome: "rejected",
        reviewed_by_user_id: user.id
      }

      changeset =
        SignupApplication.review_outcome_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      assert changeset.changes.review_outcome == :rejected
    end

    test "requires reviewed_at" do
      user = user_fixture()

      attrs = %{
        review_outcome: "approved",
        reviewed_by_user_id: user.id
      }

      changeset =
        SignupApplication.review_outcome_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).reviewed_at
    end

    test "requires review_outcome" do
      user = user_fixture()

      attrs = %{
        reviewed_at: ~U[2024-01-15 12:00:00Z],
        reviewed_by_user_id: user.id
      }

      changeset =
        SignupApplication.review_outcome_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).review_outcome
    end

    test "requires reviewed_by_user_id" do
      attrs = %{
        reviewed_at: ~U[2024-01-15 12:00:00Z],
        review_outcome: "approved"
      }

      changeset =
        SignupApplication.review_outcome_changeset(%SignupApplication{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).reviewed_by_user_id
    end
  end

  describe "database operations" do
    test "can insert and retrieve complete application" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        membership_type: "family",
        membership_eligibility: [
          "citizen_of_scandinavia",
          "speak_scandinavian_language"
        ],
        occupation: "Software Engineer",
        birth_date: ~D[1985-06-15],
        address: "456 Nordic Street",
        country: "USA",
        city: "Seattle",
        region: "WA",
        postal_code: "98101",
        place_of_birth: "Stockholm",
        citizenship: "Swedish",
        most_connected_nordic_country: "Sweden",
        link_to_scandinavia: "Grandparents from Sweden",
        lived_in_scandinavia: "Yes, for 2 years",
        spoken_languages: "Swedish, English",
        hear_about_the_club: "Friend recommendation",
        agreed_to_bylaws: true,
        started: ~U[2024-01-01 10:00:00Z],
        completed: ~U[2024-01-01 11:00:00Z],
        browser_timezone: "America/Los_Angeles"
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      {:ok, application} = Repo.insert(changeset)

      retrieved = Repo.get(SignupApplication, application.id)

      assert retrieved.user_id == user.id
      assert retrieved.membership_type == :family

      assert retrieved.membership_eligibility == [
               :citizen_of_scandinavia,
               :speak_scandinavian_language
             ]

      assert retrieved.occupation == "Software Engineer"
      assert retrieved.birth_date == ~D[1985-06-15]
      assert retrieved.address == "456 Nordic Street"
      assert retrieved.country == "USA"
      assert retrieved.city == "Seattle"
      assert retrieved.region == "WA"
      assert retrieved.postal_code == "98101"
      assert retrieved.place_of_birth == "Stockholm"
      assert retrieved.citizenship == "Swedish"
      assert retrieved.most_connected_nordic_country == "Sweden"
      assert retrieved.link_to_scandinavia == "Grandparents from Sweden"
      assert retrieved.lived_in_scandinavia == "Yes, for 2 years"
      assert retrieved.spoken_languages == "Swedish, English"
      assert retrieved.hear_about_the_club == "Friend recommendation"
      assert retrieved.agreed_to_bylaws == true
      assert retrieved.started == ~U[2024-01-01 10:00:00Z]
      assert retrieved.completed == ~U[2024-01-01 11:00:00Z]
      assert retrieved.browser_timezone == "America/Los_Angeles"
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can save application with minimal required fields" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        birth_date: ~D[1990-01-01],
        address: "123 Viking Way",
        country: "USA",
        city: "San Francisco",
        postal_code: "94107",
        place_of_birth: "Oslo",
        citizenship: "Norwegian",
        most_connected_nordic_country: "Norway",
        agreed_to_bylaws: true
      }

      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, attrs)

      assert changeset.valid?
      {:ok, application} = Repo.insert(changeset)

      assert application.membership_eligibility == [:born_in_scandinavia]
      assert application.occupation == nil
      assert application.region == nil
    end

    test "can update application with review outcome" do
      user = user_fixture()
      reviewer = user_fixture()
      application = signup_application_fixture(user)

      review_attrs = %{
        reviewed_at: ~U[2024-01-15 12:00:00Z],
        review_outcome: "approved",
        reviewed_by_user_id: reviewer.id
      }

      changeset =
        SignupApplication.review_outcome_changeset(application, review_attrs)

      {:ok, updated} = Repo.update(changeset)

      assert updated.reviewed_at == ~U[2024-01-15 12:00:00Z]
      assert updated.review_outcome == :approved
      assert updated.reviewed_by_user_id == reviewer.id
    end
  end

  describe "eligibility_options/0" do
    test "returns list of eligibility options" do
      options = SignupApplication.eligibility_options()

      assert is_list(options)
      assert length(options) == 6

      assert {"I am a citizen of a Scandinavian country (Denmark, Finland, Iceland, Norway & Sweden)",
              "citizen_of_scandinavia"} in options

      assert {"I was born in Scandinavia", "born_in_scandinavia"} in options

      assert {"I speak one of the Scandinavian languages",
              "speak_scandinavian_language"} in options

      assert {"I am the spouse of a member", "spouse_of_member"} in options
    end
  end

  describe "eligibility_lookup/0" do
    test "returns map for looking up eligibility text" do
      lookup = SignupApplication.eligibility_lookup()

      assert is_map(lookup)

      assert lookup[:citizen_of_scandinavia] ==
               "I am a citizen of a Scandinavian country (Denmark, Finland, Iceland, Norway & Sweden)"

      assert lookup[:born_in_scandinavia] == "I was born in Scandinavia"

      assert lookup[:speak_scandinavian_language] ==
               "I speak one of the Scandinavian languages"

      assert lookup[:spouse_of_member] == "I am the spouse of a member"
    end
  end

  # Helper function to create valid application attributes
  defp valid_application_attrs(overrides \\ %{}) do
    Enum.into(overrides, %{
      membership_type: "single",
      membership_eligibility: ["born_in_scandinavia"],
      birth_date: ~D[1990-01-01],
      address: "123 Viking Way",
      country: "USA",
      city: "San Francisco",
      postal_code: "94107",
      place_of_birth: "Oslo",
      citizenship: "Norwegian",
      most_connected_nordic_country: "Norway",
      agreed_to_bylaws: true
    })
  end
end
