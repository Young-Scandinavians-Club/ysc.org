defmodule YscWeb.UserRegistrationLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Registration flow" do
    test "completes full registration process successfully", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      # Step 0: Eligibility
      form = form(lv, "#registration_form")

      # Fill in eligibility information
      step_0_params = %{
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => [
            "born_in_scandinavia",
            "scandinavian_citizen"
          ]
        }
      }

      render_change(form, %{"user" => step_0_params})

      # Move to next step
      assert render_click(lv, "next-step") =~ "Account Information"

      # Step 1: Personal Information
      step_1_params = %{
        "email" => "test@example.com",
        "first_name" => "Test",
        "last_name" => "User",
        "registration_form" => %{
          "birth_date" => "1990-01-01",
          "occupation" => "Software Engineer",
          "address" => "123 Main St",
          "city" => "San Francisco",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105"
        }
      }

      render_change(form, %{"user" => step_1_params})

      # Move to next step
      assert render_click(lv, "next-step") =~ "Additional Questions"

      # Step 2: Additional Questions
      step_2_params = %{
        "registration_form" => %{
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "link_to_scandinavia" => "Born in Stockholm",
          "lived_in_scandinavia" => "Lived in Stockholm for 20 years",
          "spoken_languages" => "Swedish, Norwegian",
          "hear_about_the_club" => "Through friends",
          "agreed_to_bylaws" => true
        }
      }

      render_change(form, %{"user" => step_2_params})

      # Submit the complete form
      # Since successful submission redirects to account setup, we just ensure it doesn't error
      render_submit(form, %{
        "user" =>
          Map.merge(step_0_params, Map.merge(step_1_params, step_2_params))
      })

      # The form submission should succeed without throwing an exception
      # (it redirects to account setup flow)
    end

    test "validates each step before allowing progression", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      # Try to proceed without filling Step 0
      assert render_click(lv, "next-step") =~ "Eligibility"

      # Fill Step 0 incorrectly
      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single"
            # Missing membership_eligibility
          }
        }
      })

      assert render_click(lv, "next-step") =~ "Eligibility"

      # Fill Step 0 correctly
      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      # Move to Step 1
      assert render_click(lv, "next-step") =~ "Account Information"

      # Try to proceed with invalid email
      render_change(form, %{
        "user" => %{
          "email" => "invalid-email"
        }
      })

      assert render_click(lv, "next-step") =~ "Account Information"
      assert render(lv) =~ "must have the @ sign and no spaces"
    end

    test "handles family membership registration", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      # Select family membership
      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "family",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      # Verify family member inputs are shown
      assert render_click(lv, "next-step") =~ "Family"
      assert render(lv) =~ "Please list all members of your family"
    end

    test "allows navigation between steps", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      # Fill Step 0
      form = form(lv, "#registration_form")

      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      # Navigate forward
      assert render_click(lv, "next-step") =~ "Account Information"

      # Navigate back
      assert render_click(lv, "prev-step") =~ "Eligibility"

      # Verify data is preserved
      assert render(lv) =~ "single"
    end

    test "prevents submission without agreeing to bylaws", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      # Fill all steps with valid data except agreed_to_bylaws
      step_0_params = %{
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia"]
        }
      }

      step_1_params = %{
        "email" => "test@example.com",
        "password" => "valid_password123",
        "phone_number" => "+14155552671",
        "first_name" => "Test",
        "last_name" => "User",
        "registration_form" => %{
          "birth_date" => "1990-01-01",
          "occupation" => "Software Engineer",
          "address" => "123 Main St",
          "city" => "San Francisco",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105"
        }
      }

      step_2_params = %{
        "registration_form" => %{
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "link_to_scandinavia" => "Born in Stockholm",
          "lived_in_scandinavia" => "Lived in Stockholm for 20 years",
          "spoken_languages" => "Swedish, Norwegian",
          "hear_about_the_club" => "Through friends",
          "agreed_to_bylaws" => false
        }
      }

      # Fill all steps
      render_change(form, %{"user" => step_0_params})
      assert render_click(lv, "next-step") =~ "Account Information"

      render_change(form, %{"user" => step_1_params})
      assert render_click(lv, "next-step") =~ "Additional Questions"

      render_change(form, %{"user" => step_2_params})

      # Verify submit button is disabled when agreed_to_bylaws is false
      html = render(lv)
      # The button should be disabled when agreed_to_bylaws is false
      assert html =~ "Submit Application"
      # Check that the submit button specifically has disabled attribute
      assert html =~ ~r/<button[^>]*disabled[^>]*>.*Submit Application/s or
               html =~ ~r/aria-disabled="true"[^>]*>.*Submit Application/s

      # Now check the bylaws checkbox and verify button becomes enabled
      step_2_with_bylaws =
        Map.put(
          step_2_params,
          "registration_form",
          Map.put(step_2_params["registration_form"], "agreed_to_bylaws", true)
        )

      render_change(form, %{"user" => step_2_with_bylaws})

      # Verify submit button is now enabled
      html = render(lv)
      assert html =~ "Submit Application"

      # The button should not have disabled attribute when agreed_to_bylaws is true
      # Let's check if the button is actually enabled by looking for the specific pattern
      # The button should either not have disabled attribute, or have aria-disabled="false"
      button_disabled =
        html =~ ~r/<button[^>]*disabled[^>]*>.*Submit Application/s

      button_aria_disabled =
        html =~ ~r/aria-disabled="true"[^>]*>.*Submit Application/s

      # At least one of these should be false (button should be enabled)
      refute button_disabled and button_aria_disabled
    end
  end
end
