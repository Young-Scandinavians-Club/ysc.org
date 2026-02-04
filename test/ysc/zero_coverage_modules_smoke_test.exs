defmodule Ysc.ZeroCoverageModulesSmokeTest do
  use ExUnit.Case, async: true

  import Mox

  alias Ysc.ExpenseReports.BankAccount
  alias Ysc.Media.Timeline
  alias Ysc.Payments.PaymentDisplay

  describe "EctoEnum defenum modules" do
    test "BoardMemberPosition exposes expected values and validation" do
      assert :president in Keyword.keys(BoardMemberPosition.__enum_map__())
      assert "president" in BoardMemberPosition.__valid_values__()
      assert BoardMemberPosition.valid_value?(:president)
      assert BoardMemberPosition.valid_value?("president")
      refute BoardMemberPosition.valid_value?("not_a_real_role")
      assert BoardMemberPosition.cast("president") == {:ok, :president}
      assert BoardMemberPosition.cast("not_a_real_role") == :error
    end

    test "MembershipEligibility exposes expected values and validation" do
      assert :citizen_of_scandinavia in Keyword.keys(
               MembershipEligibility.__enum_map__()
             )

      assert MembershipEligibility.valid_value?("spouse_of_member")
      refute MembershipEligibility.valid_value?("nope")

      assert MembershipEligibility.cast("spouse_of_member") ==
               {:ok, :spouse_of_member}

      assert MembershipEligibility.cast("nope") == :error
    end

    test "SignupApplicationEventType exposes expected values and validation" do
      assert Keyword.keys(SignupApplicationEventType.__enum_map__()) ==
               [:review_started, :review_completed, :review_updated]

      assert SignupApplicationEventType.valid_value?("review_started")
      refute SignupApplicationEventType.valid_value?("created")
    end

    test "UserApplicationReviewOutcome exposes expected values and validation" do
      assert Keyword.keys(UserApplicationReviewOutcome.__enum_map__()) == [
               :approved,
               :rejected
             ]

      assert UserApplicationReviewOutcome.valid_value?("approved")
      refute UserApplicationReviewOutcome.valid_value?("pending")
    end

    test "UserNoteCategory exposes expected values and validation" do
      assert Keyword.keys(UserNoteCategory.__enum_map__()) == [
               :general,
               :violation
             ]

      assert UserNoteCategory.valid_value?("general")
      refute UserNoteCategory.valid_value?("other")
    end

    test "PostEventType exposes expected values and validation" do
      assert :post_created in Keyword.keys(PostEventType.__enum_map__())
      assert PostEventType.valid_value?("post_published")
      refute PostEventType.valid_value?("post_archived")
    end

    test "SmsReceivedStatus exposes expected values and validation" do
      assert Keyword.keys(SmsReceivedStatus.__enum_map__()) == [
               :delivered,
               :failed,
               :pending
             ]

      assert SmsReceivedStatus.valid_value?("pending")
      refute SmsReceivedStatus.valid_value?("queued")
    end

    test "ViolationFormStatus exposes expected values and validation" do
      assert Keyword.keys(ViolationFormStatus.__enum_map__()) == [
               :submitted,
               :in_review,
               :reviewed
             ]

      assert ViolationFormStatus.valid_value?("reviewed")
      refute ViolationFormStatus.valid_value?("draft")
    end

    test "ImageProcessingState exposes expected values and validation" do
      assert Keyword.keys(ImageProcessingState.__enum_map__()) == [
               :unprocessed,
               :processing,
               :completed,
               :failed
             ]

      assert ImageProcessingState.valid_value?("completed")
      refute ImageProcessingState.valid_value?("unknown")
    end
  end

  describe "Ysc.Media.Timeline.inject_date_headers/1" do
    test "injects deterministic header items per year-month group" do
      images = [
        %{id: "a", inserted_at: ~U[2024-01-05 00:00:00Z]},
        %{id: "b", inserted_at: ~U[2024-01-20 00:00:00Z]},
        %{id: "c", inserted_at: ~U[2024-02-01 00:00:00Z]}
      ]

      result = Timeline.inject_date_headers(images)

      assert [%Timeline.Header{} = h1, i1, i2, %Timeline.Header{} = h2, i3] =
               result

      assert i1.id == "a"
      assert i2.id == "b"
      assert i3.id == "c"

      assert h1.id == "header-2024-1"
      assert h1.formatted_date == "January 2024"

      assert h2.id == "header-2024-2"
      assert h2.formatted_date == "February 2024"
    end
  end

  describe "Ysc.Payments.PaymentDisplay" do
    test "returns booking-specific icon and styling based on property" do
      booking = %{property: :tahoe, reference_id: "BK-1"}

      payment = %{type: :booking, booking: booking}

      assert PaymentDisplay.get_payment_icon(payment) == "hero-home"

      assert PaymentDisplay.get_payment_icon_bg(payment) ==
               "bg-blue-50 group-hover:bg-blue-600"

      assert PaymentDisplay.get_payment_icon_color(payment) ==
               "text-blue-600 group-hover:text-white"

      assert PaymentDisplay.get_payment_title(payment) == "Tahoe Booking"
      assert PaymentDisplay.get_payment_reference(payment) == "BK-1"
    end

    test "handles ticket/membership/donation and fallback paths" do
      assert PaymentDisplay.get_payment_icon(%{type: :ticket}) == "hero-ticket"

      assert PaymentDisplay.get_payment_icon(%{type: :membership}) ==
               "hero-heart"

      assert PaymentDisplay.get_payment_icon(%{type: :donation}) == "hero-gift"
      assert PaymentDisplay.get_payment_icon(%{}) == "hero-credit-card"

      assert PaymentDisplay.get_payment_title(%{
               type: :ticket,
               event: %{title: "Gala"}
             }) == "Gala"

      assert PaymentDisplay.get_payment_title(%{type: :ticket}) ==
               "Event Tickets"

      assert PaymentDisplay.get_payment_title(%{type: :membership}) ==
               "Membership Payment"

      assert PaymentDisplay.get_payment_title(%{type: :donation}) == "Donation"

      assert PaymentDisplay.get_payment_title(%{description: "Custom"}) ==
               "Custom"

      assert PaymentDisplay.get_payment_title(%{}) == "Payment"

      assert PaymentDisplay.get_payment_reference(%{
               ticket_order: %{reference_id: nil}
             }) == "—"

      assert PaymentDisplay.get_payment_reference(%{
               payment: %{reference_id: "PM-9"}
             }) == "PM-9"

      assert PaymentDisplay.get_payment_reference(%{}) == "—"
    end
  end

  describe "Ysc.ExpenseReports.BankAccount changeset + safe serialization" do
    test "extracts last 4 digits and enforces routing checksum" do
      # Known-valid ABA routing number (JPMorgan Chase, commonly used example)
      valid_routing = "021000021"

      attrs = %{
        user_id: Ecto.ULID.generate(),
        routing_number: valid_routing,
        account_number: "000012341234",
        account_number_last_4: nil
      }

      changeset = BankAccount.changeset(%BankAccount{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :account_number_last_4) ==
               "1234"
    end

    test "rejects invalid routing numbers and invalid account numbers" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        routing_number: "021000022",
        account_number: "12AB"
      }

      changeset = BankAccount.changeset(%BankAccount{}, attrs)
      refute changeset.valid?

      errors =
        Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

      assert errors.routing_number == ["is not a valid US routing number"]
      assert errors.account_number == ["must contain only digits"]
    end

    test "Inspect and Jason.Encoder implementations never include sensitive numbers" do
      bank_account = %BankAccount{
        id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        routing_number: "021000021",
        account_number: "000000001234",
        account_number_last_4: "1234",
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-02 00:00:00Z]
      }

      inspected = inspect(bank_account)
      refute String.contains?(inspected, "021000021")
      refute String.contains?(inspected, "000000001234")
      assert String.contains?(inspected, "account_number_last_4")

      json = Jason.encode!(bank_account)
      refute String.contains?(json, "021000021")
      refute String.contains?(json, "000000001234")
      assert String.contains?(json, "account_number_last_4")
    end
  end

  describe "Ysc.Media.Image (Flop.Schema derive)" do
    test "exports Flop schema metadata" do
      assert Flop.Schema.filterable(%Ysc.Media.Image{}) == [
               :title,
               :alt_text,
               :user_id
             ]

      assert Flop.Schema.sortable(%Ysc.Media.Image{}) == [:inserted_at]
    end
  end

  describe "Ysc.Cldr (Cldr backend)" do
    test "is configured for :en" do
      locale = Cldr.default_locale(Ysc.Cldr)
      assert %Cldr.LanguageTag{} = locale
      assert locale.language == "en"

      assert :en in Ysc.Cldr.known_locale_names()
    end
  end

  describe "Ysc.Application.config_change/3" do
    test "returns :ok" do
      assert Ysc.Application.config_change(%{}, %{}, []) == :ok
    end
  end

  describe "Stripe.CustomerMock (Mox mock)" do
    setup :verify_on_exit!

    test "implements Stripe.CustomerBehaviour via Mox" do
      Mox.expect(Stripe.CustomerMock, :retrieve, fn id, opts ->
        assert id == "cus_123"
        assert opts == []
        {:ok, %Stripe.Customer{id: "cus_123"}}
      end)

      Mox.expect(Stripe.CustomerMock, :update, fn id, params, opts ->
        assert id == "cus_123"
        assert params == %{email: "new@example.com"}
        assert opts == []
        {:ok, %Stripe.Customer{id: "cus_123", email: "new@example.com"}}
      end)

      assert {:ok, %Stripe.Customer{id: "cus_123"}} =
               Stripe.CustomerMock.retrieve("cus_123", [])

      assert {:ok, %Stripe.Customer{id: "cus_123", email: "new@example.com"}} =
               Stripe.CustomerMock.update(
                 "cus_123",
                 %{email: "new@example.com"},
                 []
               )
    end
  end
end
