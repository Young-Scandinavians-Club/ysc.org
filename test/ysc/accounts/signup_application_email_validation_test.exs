defmodule Ysc.Accounts.SignupApplicationEmailValidationTest do
  @moduledoc """
  Signup application production email validation tests.

  Runs with `async: false` because these tests mutate global `:environment` and
  share the disposable-domain ETS table with other suites under full-suite runs.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Accounts.SignupApplication
  alias Ysc.Newsletter.EmailValidator

  import Ysc.AccountsFixtures
  import Ysc.EmailValidatorTestHelper

  setup do
    EmailValidator.init_ets_table()
    ensure_disposable_domain!("mailinator.com")
    :ok
  end

  describe "email validation in production" do
    test "does not validate email in dev environment" do
      Ysc.Test.EnvHelper.with_environment("dev", fn ->
        user = user_fixture_fast(%{email: "test@mailinator.com"})

        attrs =
          valid_application_attrs(%{
            user_id: user.id
          })

        changeset =
          SignupApplication.application_changeset(%SignupApplication{}, attrs)

        assert changeset.valid?
      end)
    end

    test "does not validate email in sandbox environment" do
      Ysc.Test.EnvHelper.with_environment("sandbox", fn ->
        user = user_fixture_fast(%{email: "test@mailinator.com"})

        attrs =
          valid_application_attrs(%{
            user_id: user.id
          })

        changeset =
          SignupApplication.application_changeset(%SignupApplication{}, attrs)

        assert changeset.valid?
      end)
    end

    test "validates email in production environment with valid email" do
      Ysc.Test.EnvHelper.with_environment("production", fn ->
        user = user_fixture_fast(%{email: "test@example.com"})

        attrs =
          valid_application_attrs(%{
            user_id: user.id
          })

        Process.delete({:mx_cache, "example.com"})

        with_mx_resolver_override(fn _domain -> :ok end, fn ->
          changeset =
            SignupApplication.application_changeset(%SignupApplication{}, attrs)

          assert changeset.valid?
        end)
      end)
    end

    test "blocks disposable email in production environment" do
      Ysc.Test.EnvHelper.with_environment("production", fn ->
        ensure_disposable_domain!("mailinator.com")

        user = user_fixture_fast(%{email: "test@mailinator.com"})

        attrs =
          valid_application_attrs(%{
            user_id: user.id
          })

        changeset =
          SignupApplication.application_changeset(%SignupApplication{}, attrs)

        refute changeset.valid?

        assert "Email address appears to be a temporary or disposable email. Please use a permanent email address." in errors_on(
                 changeset
               ).base
      end)
    end

    test "blocks email with no MX records in production environment" do
      Ysc.Test.EnvHelper.with_environment("production", fn ->
        domain = "mx-reject-#{System.unique_integer([:positive])}.example.org"
        email = "user@#{domain}"

        with_mx_resolver_override(
          fn _domain -> {:error, :no_mx_records} end,
          fn ->
            user = user_fixture_fast(%{email: email})
            Process.delete({:mx_cache, domain})

            attrs =
              valid_application_attrs(%{
                user_id: user.id
              })

            changeset =
              SignupApplication.application_changeset(
                %SignupApplication{},
                attrs
              )

            refute changeset.valid?

            assert "Email domain cannot receive mail. Please check your email address." in errors_on(
                     changeset
                   ).base
          end
        )
      end)
    end

    test "respects validate_email option override to force validation" do
      Ysc.Test.EnvHelper.with_environment("dev", fn ->
        ensure_disposable_domain!("mailinator.com")

        user = user_fixture_fast(%{email: "test@mailinator.com"})

        attrs =
          valid_application_attrs(%{
            user_id: user.id
          })

        changeset =
          SignupApplication.application_changeset(%SignupApplication{}, attrs,
            validate_email: true
          )

        refute changeset.valid?

        assert "Email address appears to be a temporary or disposable email. Please use a permanent email address." in errors_on(
                 changeset
               ).base
      end)
    end

    test "respects validate_email option override to skip validation" do
      Ysc.Test.EnvHelper.with_environment("production", fn ->
        user = user_fixture_fast(%{email: "test@mailinator.com"})

        attrs =
          valid_application_attrs(%{
            user_id: user.id
          })

        changeset =
          SignupApplication.application_changeset(%SignupApplication{}, attrs,
            validate_email: false
          )

        assert changeset.valid?
      end)
    end

    test "fails open when user_id is nil" do
      Ysc.Test.EnvHelper.with_environment("production", fn ->
        attrs =
          valid_application_attrs(%{
            user_id: nil
          })

        changeset =
          SignupApplication.application_changeset(%SignupApplication{}, attrs)

        assert changeset.valid?
      end)
    end

    test "fails open when user does not exist" do
      Ysc.Test.EnvHelper.with_environment("production", fn ->
        non_existent_id = Ecto.ULID.generate()

        attrs =
          valid_application_attrs(%{
            user_id: non_existent_id
          })

        changeset =
          SignupApplication.application_changeset(%SignupApplication{}, attrs)

        assert changeset.valid?
      end)
    end

    test "fails open on validation exceptions" do
      Ysc.Test.EnvHelper.with_environment("production", fn ->
        user = user_fixture_fast(%{email: "test@example.com"})

        attrs =
          valid_application_attrs(%{
            user_id: user.id
          })

        Process.delete({:mx_cache, "example.com"})

        with_mx_resolver_override(
          fn _domain -> raise "Simulated error" end,
          fn ->
            changeset =
              SignupApplication.application_changeset(
                %SignupApplication{},
                attrs
              )

            assert changeset.valid?
          end
        )
      end)
    end
  end

  defp valid_application_attrs(overrides) do
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
