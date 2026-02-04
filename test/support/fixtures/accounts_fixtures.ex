defmodule Ysc.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"
  def valid_user_first_name, do: "John"
  def valid_user_last_name, do: "Doe"

  def valid_user_attributes(attrs \\ %{}) do
    attrs
    |> normalize_enum_attrs()
    |> Enum.into(%{
      email: unique_user_email(),
      password: valid_user_password(),
      first_name: valid_user_first_name(),
      last_name: valid_user_last_name(),
      phone_number: "+14159098268",
      state: "active",
      role: "member"
    })
  end

  # Convert atom enum values to strings for EctoEnum compatibility
  defp normalize_enum_attrs(attrs) do
    attrs
    |> Enum.map(fn
      {:state, state} when is_atom(state) -> {:state, Atom.to_string(state)}
      {:role, role} when is_atom(role) -> {:role, Atom.to_string(role)}
      other -> other
    end)
    |> Enum.into(%{})
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Ysc.Accounts.register_user()

    user
  end

  @doc """
  Creates a user without a password (like an OAuth user).
  Directly inserts into the database to bypass password requirement.
  """
  def oauth_user_fixture(attrs \\ %{}) do
    user_attrs =
      %{
        email: unique_user_email(),
        first_name: valid_user_first_name(),
        last_name: valid_user_last_name(),
        phone_number: "+14159098268",
        state: :active,
        role: :member,
        hashed_password: nil,
        password_set_at: nil,
        confirmed_at: DateTime.utc_now()
      }
      |> Map.merge(Enum.into(attrs, %{}))

    %Ysc.Accounts.User{}
    |> Ysc.Accounts.User.registration_changeset(user_attrs)
    |> Ysc.Repo.insert!()
  end

  def extract_user_token(fun) do
    {:ok, captured} = fun.(&"[TOKEN]#{&1}[TOKEN]")

    case captured do
      [token] when is_binary(token) ->
        token

      %{text: text} ->
        [_, token | _] = String.split(text, "[TOKEN]")
        token

      # Handle the email notification format
      %{text_body: token} ->
        token

      text when is_binary(text) ->
        [_, token | _] = String.split(text, "[TOKEN]")
        token
    end
  end

  @doc """
  Creates a valid COSE public key map for testing.
  """
  def valid_cose_public_key do
    %{
      # x coordinate
      -3 => :crypto.strong_rand_bytes(32),
      # y coordinate
      -2 => :crypto.strong_rand_bytes(32),
      # curve
      -1 => 1,
      # kty (key type)
      1 => 2,
      # alg (algorithm: ES256)
      3 => -7
    }
  end

  @doc """
  Creates a passkey fixture for a user.
  """
  def passkey_fixture(user, attrs \\ %{}) do
    credential_id = attrs[:external_id] || :crypto.strong_rand_bytes(16)
    public_key_map = attrs[:public_key_map] || valid_cose_public_key()

    default_attrs = %{
      external_id: credential_id,
      public_key: Ysc.Accounts.UserPasskey.encode_public_key(public_key_map),
      nickname: attrs[:nickname] || "Test Device",
      sign_count: attrs[:sign_count] || 0
    }

    attrs = Map.merge(default_attrs, attrs)
    {:ok, passkey} = Ysc.Accounts.create_user_passkey(user, attrs)
    passkey
  end

  def signup_application_fixture(user, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        user_id: user.id,
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        occupation: "Developer",
        birth_date: ~D[1990-01-01],
        address: "123 Viking Way",
        country: "USA",
        city: "San Francisco",
        postal_code: "94107",
        place_of_birth: "Oslo",
        citizenship: "Norwegian",
        most_connected_nordic_country: "Norway",
        agreed_to_bylaws: true,
        completed: DateTime.utc_now()
      })

    {:ok, application} =
      %Ysc.Accounts.SignupApplication{}
      |> Ysc.Accounts.SignupApplication.application_changeset(attrs)
      |> Ysc.Repo.insert()

    application
  end
end
