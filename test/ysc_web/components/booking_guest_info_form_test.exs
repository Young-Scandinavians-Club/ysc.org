defmodule YscWeb.Components.BookingGuestInfoFormTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.Components.BookingGuestInfoForm

  alias Ysc.Bookings.Booking

  describe "booking_guest_info_form/1" do
    test "renders guest form with intro text and submit button" do
      booking = %Booking{
        guests_count: 2,
        children_count: 1,
        rooms: [%{name: "Lakeview"}]
      }

      guest_info_form =
        to_form(
          %{
            "0" => %{
              "first_name" => "Pat",
              "last_name" => "Member",
              "is_booking_user" => true,
              "is_child" => false,
              "order_index" => 0
            },
            "1" => %{
              "first_name" => "",
              "last_name" => "",
              "is_booking_user" => false,
              "is_child" => false,
              "order_index" => 1
            },
            "2" => %{
              "first_name" => "",
              "last_name" => "",
              "is_booking_user" => false,
              "is_child" => true,
              "order_index" => 2
            }
          },
          as: "guests"
        )

      assigns = %{
        booking: booking,
        guest_info_form: guest_info_form,
        guest_info_errors: %{},
        other_family_members: [],
        selected_family_members_for_guests: %{},
        current_user: nil,
        intro_text: "Custom intro for checkout",
        submit_label: "Continue to Payment"
      }

      heex = ~H"""
      <.booking_guest_info_form
        id="guest-info-form"
        booking={@booking}
        guest_info_form={@guest_info_form}
        guest_info_errors={@guest_info_errors}
        other_family_members={@other_family_members}
        selected_family_members_for_guests={@selected_family_members_for_guests}
        current_user={@current_user}
        intro_text={@intro_text}
        submit_label={@submit_label}
      />
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="guest-info-form"|
      assert html =~ "Guest Information"
      assert html =~ "Custom intro for checkout"
      assert html =~ "You (the member making this booking)"
      assert html =~ "Pat"
      assert html =~ "Member"
      assert html =~ "Adult Guest"
      assert html =~ "Child Guest"
      assert html =~ "Continue to Payment"
      assert html =~ ~s|name="guests[1][first_name]"|
      assert html =~ ~s|type="hidden" name="guests[0][first_name]"|
    end

    test "renders error summary and action slot" do
      booking = %Booking{guests_count: 1, children_count: 0, rooms: []}

      guest_info_form =
        to_form(
          %{
            "0" => %{
              "first_name" => "Pat",
              "last_name" => "Member",
              "is_booking_user" => true,
              "is_child" => false,
              "order_index" => 0
            }
          },
          as: "guests"
        )

      assigns = %{
        booking: booking,
        guest_info_form: guest_info_form,
        guest_info_errors: %{
          "1" => %{first_name: ["can't be blank"]},
          :general => "Guest information is required"
        },
        other_family_members: [],
        selected_family_members_for_guests: %{},
        current_user: nil
      }

      heex = ~H"""
      <.booking_guest_info_form
        booking={@booking}
        guest_info_form={@guest_info_form}
        guest_info_errors={@guest_info_errors}
        other_family_members={@other_family_members}
        selected_family_members_for_guests={@selected_family_members_for_guests}
        current_user={@current_user}
      >
        <:actions>
          <button type="button" id="cancel-booking">Cancel</button>
        </:actions>
      </.booking_guest_info_form>
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="guest-errors-summary"|
      assert html =~ "missing required information"
      assert html =~ ~s|id="guest-error-general"|
      assert html =~ "Guest information is required"
      assert html =~ ~s|id="cancel-booking"|
    end
  end
end
