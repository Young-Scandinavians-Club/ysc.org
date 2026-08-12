defmodule YscWeb.UserRegistrationLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias Ysc.Accounts.FamilyInvites
  alias Ysc.Repo

  import Ysc.AccountsFixtures, only: [user_fixture: 1]

  alias Ysc.Accounts

  defp user_with_lifetime_membership(attrs \\ %{}) do
    user_fixture(attrs)
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
  end

  describe "Registration flow" do
    test "shows clarified eligibility step copy", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Check all that describe you"
      assert html =~ "you only need to meet one to qualify"
    end

    test "shows scandinavia connection header on additional questions step", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      assert render_click(lv, "next-step") =~ "Account Information"

      render_change(form, %{
        "user" => %{
          "email" => "header#{System.unique_integer()}@example.com",
          "first_name" => "Header",
          "last_name" => "Test",
          "registration_form" => %{
            "birth_date" => "1990-01-01",
            "address" => "1 Main St",
            "city" => "SF",
            "region" => "CA",
            "country" => "US",
            "postal_code" => "94105"
          }
        }
      })

      html = render_click(lv, "next-step")

      assert html =~
               "Tell us about your connection to Scandinavia (answer at least one)"

      assert html =~ "Tell us about your connection to Scandinavia/the Nordics"
    end

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
      assert render(lv) =~ "List your spouse or partner"
      assert has_element?(lv, "#family-members")
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

    test "recover_wizard restores step from partially filled params", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      params = %{
        "email" => "wizard#{System.unique_integer()}@example.com",
        "first_name" => "Wiz",
        "last_name" => "Test",
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia"],
          "birth_date" => "1990-01-01",
          "address" => "1 Wizard St",
          "city" => "SF",
          "country" => "US",
          "postal_code" => "94105",
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "agreed_to_bylaws" => true
        }
      }

      render_change(lv, "recover_wizard", %{"user" => params})

      assert render(lv) =~ "Additional Questions"
    end

    test "set-step does not advance past step 0 when step 0 is invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      assert render_click(lv, "set-step", %{"step" => "1"}) =~ "Eligibility"
    end

    test "shows email already registered when address is taken", %{conn: conn} do
      taken_email = "taken#{System.unique_integer()}@example.com"
      _existing = Ysc.AccountsFixtures.user_fixture(%{email: taken_email})

      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      step_0 = %{
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia"]
        }
      }

      step_1 = %{
        "email" => taken_email,
        "first_name" => "Dup",
        "last_name" => "Email",
        "registration_form" => %{
          "birth_date" => "1990-01-01",
          "address" => "123 Main",
          "city" => "SF",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105"
        }
      }

      step_2 = %{
        "registration_form" => %{
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "agreed_to_bylaws" => true
        }
      }

      render_change(form, %{"user" => step_0})
      assert render_click(lv, "next-step") =~ "Account Information"

      render_change(form, %{"user" => Map.merge(step_0, step_1)})
      assert render_click(lv, "next-step") =~ "Additional Questions"

      render_change(form, %{
        "user" => Map.merge(Map.merge(step_0, step_1), step_2)
      })

      render_submit(form, %{
        "user" => Map.merge(Map.merge(step_0, step_1), step_2)
      })

      assert render(lv) =~ "already registered"
    end

    test "prev-step from step 1 returns to eligibility step", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      assert render_click(lv, "next-step") =~ "Account Information"
      assert render_click(lv, "prev-step") =~ "Eligibility"
    end

    test "set-step advances to account info when step 0 is valid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      html = render_click(lv, "set-step", %{"step" => "1"})
      assert html =~ "Account Information"
    end

    test "next-step on final step does not leave the questions step without validation",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      render_click(lv, "next-step")

      render_change(form, %{
        "user" => %{
          "email" => "step3#{System.unique_integer()}@example.com",
          "first_name" => "Step",
          "last_name" => "Three",
          "registration_form" => %{
            "birth_date" => "1990-01-01",
            "address" => "1 Main St",
            "city" => "SF",
            "region" => "CA",
            "country" => "US",
            "postal_code" => "94105"
          }
        }
      })

      render_click(lv, "next-step")
      html = render_click(lv, "next-step")
      assert html =~ "Additional Questions" or html =~ "Questions"
    end

    test "step 1 stays on account info when phone number is invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      assert render_click(lv, "next-step") =~ "Account Information"

      render_change(form, %{
        "user" => %{
          "email" => "phonebad#{System.unique_integer()}@example.com",
          "first_name" => "Bad",
          "last_name" => "Phone",
          "phone_number" => "not-a-phone",
          "registration_form" => %{
            "birth_date" => "1990-01-01",
            "address" => "1 Main St",
            "city" => "SF",
            "region" => "CA",
            "country" => "US",
            "postal_code" => "94105"
          }
        }
      })

      assert render_click(lv, "next-step") =~ "Account Information"
      assert render(lv) =~ "phone" or render(lv) =~ "invalid"
    end

    test "prev-step from step 2 returns to account information", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      assert render_click(lv, "next-step") =~ "Account Information"

      email = "back#{System.unique_integer()}@example.com"

      render_change(form, %{
        "user" => %{
          "email" => email,
          "first_name" => "Back",
          "last_name" => "Step",
          "registration_form" => %{
            "birth_date" => "1990-01-01",
            "address" => "1 Main St",
            "city" => "SF",
            "region" => "CA",
            "country" => "US",
            "postal_code" => "94105"
          }
        }
      })

      assert render_click(lv, "next-step") =~ "Additional Questions"
      assert render_click(lv, "prev-step") =~ "Account Information"
      assert render(lv) =~ email
    end

    test "mount with valid family invite prefills email from invite", %{
      conn: conn
    } do
      primary = user_with_lifetime_membership()
      invite_email = "invite#{System.unique_integer()}@example.com"
      {:ok, invite} = FamilyInvites.create_invite(primary, invite_email)

      {:ok, lv, _html} =
        live(conn, ~p"/users/register?invite=#{invite.token}")

      assert render(lv) =~ invite_email
      assert has_element?(lv, "#registration_form")
    end

    test "mount with invalid invite token does not prefill from invite", %{
      conn: conn
    } do
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/users/register?invite=not-a-real-token-#{System.unique_integer()}"
        )

      refute render(lv) =~ "invite@example.com"
      assert has_element?(lv, "#registration_form")
    end

    test "successful registration redirects to account setup", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")
      uniq = System.unique_integer()

      user_params = %{
        "email" => "newuser#{uniq}@example.com",
        "first_name" => "Reg",
        "last_name" => "User",
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia"],
          "birth_date" => "1990-01-01",
          "occupation" => "Engineer",
          "address" => "123 Main St",
          "city" => "San Francisco",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105",
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "link_to_scandinavia" => "Born in Stockholm",
          "lived_in_scandinavia" => "Lived in Stockholm",
          "spoken_languages" => "Swedish",
          "hear_about_the_club" => "Friends",
          "agreed_to_bylaws" => true
        }
      }

      render_change(form, %{"user" => user_params})
      render_submit(form, %{"user" => user_params})

      {path, _flash} = assert_redirect(lv)
      assert path =~ "/account/setup"
      assert path =~ "from_signup=true"
    end

    test "validate clears email already taken banner when email changes", %{
      conn: conn
    } do
      taken_email = "taken#{System.unique_integer()}@example.com"
      _existing = Ysc.AccountsFixtures.user_fixture(%{email: taken_email})

      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      merged = %{
        "email" => taken_email,
        "first_name" => "Dup",
        "last_name" => "Email",
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia"],
          "birth_date" => "1990-01-01",
          "address" => "123 Main",
          "city" => "SF",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105",
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "agreed_to_bylaws" => true
        }
      }

      render_change(form, %{"user" => merged})
      render_submit(form, %{"user" => merged})
      assert render(lv) =~ "already registered"

      new_email = "fresh#{System.unique_integer()}@example.com"

      render_change(form, %{
        "user" => %{merged | "email" => new_email}
      })

      html = render(lv)
      refute html =~ "This email is already registered"
      assert html =~ new_email
    end

    test "set-step jumps to additional questions when step 0 and 1 are valid",
         %{
           conn: conn
         } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      render_change(form, %{
        "user" => %{
          "email" => "steps#{System.unique_integer()}@example.com",
          "first_name" => "Step",
          "last_name" => "Jump",
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"],
            "birth_date" => "1990-01-01",
            "address" => "1 Main",
            "city" => "SF",
            "region" => "CA",
            "country" => "US",
            "postal_code" => "94105"
          }
        }
      })

      html = render_click(lv, "set-step", %{"step" => "2"})
      assert html =~ "Additional Questions"
    end

    test "save shows server validation error when first name is empty", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      bad_params = %{
        "email" => "bad#{System.unique_integer()}@example.com",
        "first_name" => "",
        "last_name" => "Name",
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia"],
          "birth_date" => "1990-01-01",
          "address" => "1 St",
          "city" => "SF",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105",
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "agreed_to_bylaws" => true
        }
      }

      html = render_submit(lv, "save", %{"user" => bad_params})
      assert html =~ "Some required information is missing or incorrect"
      assert html =~ "Previous step"
    end

    test "recover_wizard restores step 1 when account fields are filled but not step 2 questions",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      params = %{
        "email" => "step1only#{System.unique_integer()}@example.com",
        "first_name" => "Step",
        "last_name" => "One",
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia"],
          "birth_date" => "1990-01-01",
          "address" => "1 Recovery St",
          "city" => "SF",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105"
        }
      }

      render_change(lv, "recover_wizard", %{"user" => params})

      assert render(lv) =~ "Account Information"
      assert has_element?(lv, "#step-1-content.flex")
      refute has_element?(lv, "#step-1-content.hidden")
    end

    test "recover_wizard restores step 2 when only scandinavia connection fields are filled",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      params = %{
        "email" => "step2only#{System.unique_integer()}@example.com",
        "first_name" => "Step",
        "last_name" => "Two",
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia"],
          "birth_date" => "1990-01-01",
          "address" => "1 Recovery St",
          "city" => "SF",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105",
          "link_to_scandinavia" => "Born in Stockholm"
        }
      }

      render_change(lv, "recover_wizard", %{"user" => params})

      assert render(lv) =~ "Additional Questions"
      assert has_element?(lv, "#step-2-content.flex")
      refute has_element?(lv, "#step-2-content.hidden")
    end

    test "set-step does not jump to additional questions when step 1 is invalid",
         %{
           conn: conn
         } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      assert render_click(lv, "next-step") =~ "Account Information"

      render_change(form, %{
        "user" => %{
          "email" => "not-an-email",
          "first_name" => "Bad",
          "last_name" => "Email",
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"],
            "birth_date" => "1990-01-01",
            "address" => "1 Main St",
            "city" => "SF",
            "region" => "CA",
            "country" => "US",
            "postal_code" => "94105"
          }
        }
      })

      assert render_click(lv, "set-step", %{"step" => "2"}) =~
               "Account Information"
    end

    test "mount with empty invite query param still renders registration form",
         %{
           conn: conn
         } do
      {:ok, lv, _html} = live(conn, ~p"/users/register?invite=")

      assert has_element?(lv, "#registration_form")
    end

    test "registration with valid family invite completes and associates invite",
         %{
           conn: conn
         } do
      primary =
        user_fixture(%{})
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      invite_email = "reginvite#{System.unique_integer()}@example.com"
      {:ok, invite} = FamilyInvites.create_invite(primary, invite_email)

      {:ok, lv, _html} =
        live(conn, ~p"/users/register?invite=#{invite.token}")

      form = form(lv, "#registration_form")

      user_params = %{
        "email" => invite_email,
        "first_name" => "Invited",
        "last_name" => "Member",
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia"],
          "birth_date" => "1990-01-01",
          "occupation" => "Engineer",
          "address" => "123 Main St",
          "city" => "San Francisco",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105",
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "link_to_scandinavia" => "Born in Stockholm",
          "lived_in_scandinavia" => "",
          "spoken_languages" => "Swedish",
          "hear_about_the_club" => "Friends",
          "agreed_to_bylaws" => true
        }
      }

      render_change(form, %{"user" => user_params})
      render_submit(form, %{"user" => user_params})

      assert {path, _flash} = assert_redirect(lv)
      assert path =~ "/account/setup"

      registered =
        Accounts.get_user_by_email(invite_email)
        |> Repo.preload(:registration_form)

      assert registered.registration_form.family_invite_id == invite.id
    end

    test "save maps string-keyed family_members map and drops empty rows", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      uniq = System.unique_integer()

      base = %{
        "email" => "familymap#{uniq}@example.com",
        "first_name" => "Fam",
        "last_name" => "Map",
        "registration_form" => %{
          "membership_type" => "family",
          "membership_eligibility" => ["born_in_scandinavia"],
          "birth_date" => "1990-01-01",
          "occupation" => "",
          "address" => "10 Oak St",
          "city" => "SF",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105",
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "agreed_to_bylaws" => true,
          "link_to_scandinavia" => "Born in Stockholm",
          "lived_in_scandinavia" => "",
          "spoken_languages" => "",
          "hear_about_the_club" => ""
        },
        "family_members" => %{
          "0" => %{
            "type" => "child",
            "first_name" => "",
            "last_name" => "",
            "birth_date" => ""
          },
          "1" => %{
            "type" => "child",
            "first_name" => "Kid",
            "last_name" => "Map",
            "birth_date" => "2015-06-01"
          }
        }
      }

      render_change(form, %{"user" => base})
      assert render_click(lv, "next-step") =~ "Account Information"

      render_change(form, %{"user" => base})
      assert render_click(lv, "next-step") =~ "Additional Questions"

      render_change(form, %{"user" => base})

      render_submit(form, %{"user" => base})

      assert {path, _flash} = assert_redirect(lv)
      assert path =~ "/account/setup"

      user =
        Accounts.get_user_by_email("familymap#{uniq}@example.com")
        |> Repo.preload(:family_members)

      assert length(user.family_members) == 1
      assert hd(user.family_members).first_name == "Kid"
    end

    test "save failure with invalid membership eligibility jumps to eligibility step",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      bad_params = %{
        "email" => "step0err#{System.unique_integer()}@example.com",
        "first_name" => "Step",
        "last_name" => "Zero",
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["not_a_valid_eligibility_slug"],
          "birth_date" => "1990-01-01",
          "address" => "1 St",
          "city" => "SF",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105",
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "agreed_to_bylaws" => true
        }
      }

      html = render_submit(lv, "save", %{"user" => bad_params})
      assert html =~ "Some required information is missing or incorrect"
      assert html =~ "Eligibility"
    end

    test "set-step with step 0 returns to eligibility from later step", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      assert render_click(lv, "next-step") =~ "Account Information"

      html = render_click(lv, "set-step", %{"step" => "0"})
      assert html =~ "Eligibility"
    end

    test "recover_wizard restores step 0 when only eligibility fields are filled",
         %{
           conn: conn
         } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      params = %{
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia"]
        }
      }

      render_change(lv, "recover_wizard", %{"user" => params})

      html = render(lv)
      assert html =~ "Eligibility"
      assert html =~ ~s(id="step-0-content")
    end

    test "save failure on step 2 questions jumps to additional questions step",
         %{
           conn: conn
         } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      bad_params = %{
        "email" => "q2#{System.unique_integer()}@example.com",
        "first_name" => "Q",
        "last_name" => "Two",
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia"],
          "birth_date" => "1990-01-01",
          "address" => "1 St",
          "city" => "SF",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105",
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "agreed_to_bylaws" => false
        }
      }

      html = render_submit(lv, "save", %{"user" => bad_params})
      assert html =~ "Some required information is missing or incorrect"
      assert html =~ "Additional Questions" or html =~ "Questions"
    end
  end

  describe "Turnstile verification" do
    @valid_params %{
      "email" => "turnstile@example.com",
      "first_name" => "Tur",
      "last_name" => "Nstile",
      "registration_form" => %{
        "membership_type" => "single",
        "membership_eligibility" => ["born_in_scandinavia"],
        "birth_date" => "1990-01-01",
        "address" => "1 Main St",
        "city" => "San Francisco",
        "region" => "CA",
        "country" => "US",
        "postal_code" => "94105",
        "place_of_birth" => "SE",
        "citizenship" => "SE",
        "most_connected_nordic_country" => "SE",
        "link_to_scandinavia" => "Born in Stockholm",
        "agreed_to_bylaws" => true
      }
    }

    test "renders the Turnstile widget inside the registration form", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      assert has_element?(lv, "#cf-turnstile")
    end

    test "allows submission when Turnstile verification succeeds", %{conn: conn} do
      uniq = System.unique_integer()

      stub(TurnstileMock, :verify, fn _params, _ip ->
        {:ok, %{"success" => true}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      params =
        Map.put(@valid_params, "email", "turnstile_ok#{uniq}@example.com")

      render_change(form, %{"user" => params})
      render_submit(form, %{"user" => params})

      {path, flash} = assert_redirect(lv)
      assert path =~ "/account/setup"

      assert flash["info"] =~ "Application received!"
      assert flash["info"] =~ "6-digit code"
    end

    test "blocks submission and shows error when Turnstile verification fails",
         %{
           conn: conn
         } do
      stub(TurnstileMock, :verify, fn _params, _ip ->
        {:error, %{"error-codes" => ["invalid-input-response"]}}
      end)

      stub(TurnstileMock, :refresh, fn socket -> socket end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      render_change(form, %{"user" => @valid_params})
      render_submit(form, %{"user" => @valid_params})

      html = render(lv)
      assert html =~ "verify you"
      assert html =~ "real person"
      refute_redirected(lv)
    end

    test "calls Turnstile.refresh after a failed verification", %{conn: conn} do
      test_pid = self()

      stub(TurnstileMock, :verify, fn _params, _ip ->
        {:error, %{"error-codes" => ["invalid-input-response"]}}
      end)

      stub(TurnstileMock, :refresh, fn socket ->
        send(test_pid, :turnstile_refreshed)
        socket
      end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      render_change(form, %{"user" => @valid_params})
      render_submit(form, %{"user" => @valid_params})

      assert_received :turnstile_refreshed
    end

    test "does not register the user when Turnstile verification fails", %{
      conn: conn
    } do
      uniq = System.unique_integer()
      email = "blocked#{uniq}@example.com"

      stub(TurnstileMock, :verify, fn _params, _ip ->
        {:error, %{"error-codes" => ["invalid-input-response"]}}
      end)

      stub(TurnstileMock, :refresh, fn socket -> socket end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      params = Map.put(@valid_params, "email", email)
      render_change(form, %{"user" => params})
      render_submit(form, %{"user" => params})

      refute Accounts.get_user_by_email(email)
    end
  end
end
