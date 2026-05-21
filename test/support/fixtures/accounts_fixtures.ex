defmodule Ysc.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Accounts` context.
  """

  def unique_user_email, do: "user-#{Ecto.UUID.generate()}@example.com"

  def unique_user_phone do
    n = System.unique_integer([:monotonic, :positive])

    # Valid NANP: +1 + area code 206 (Seattle) + exchange 200-299 (starts with 2) + 4-digit station
    exchange = 200 + rem(div(n, 10_000), 100)
    station = rem(n, 10_000)
    "+1206#{exchange}#{String.pad_leading(Integer.to_string(station), 4, "0")}"
  end

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
      phone_number: unique_user_phone(),
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
    attrs = Map.new(attrs)
    role = Map.get(attrs, :role)
    state = Map.get(attrs, :state)

    {:ok, user} =
      attrs
      |> Map.drop([:role, :state])
      |> valid_user_attributes()
      |> Ysc.Accounts.register_user()

    apply_fixture_role_state(user, role, state)
  end

  defp apply_fixture_role_state(user, nil, nil), do: user

  defp apply_fixture_role_state(user, role, state) do
    attrs =
      %{}
      |> maybe_put_enum(:role, role)
      |> maybe_put_enum(:state, state)

    user
    |> Ysc.Accounts.User.update_user_changeset(attrs)
    |> Ysc.Repo.update!()
  end

  defp maybe_put_enum(attrs, _key, nil), do: attrs

  defp maybe_put_enum(attrs, key, value) when is_atom(value),
    do: Map.put(attrs, key, Atom.to_string(value))

  defp maybe_put_enum(attrs, key, value), do: Map.put(attrs, key, value)

  @doc """
  Creates a user without a password (like an OAuth user).
  Directly inserts into the database to bypass password requirement.
  """
  def oauth_user_fixture(attrs \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    attrs = Map.new(attrs)
    role = Map.get(attrs, :role, :member)
    state = Map.get(attrs, :state, :active)

    user_attrs =
      %{
        email: unique_user_email(),
        first_name: valid_user_first_name(),
        last_name: valid_user_last_name(),
        phone_number: unique_user_phone(),
        hashed_password: nil,
        password_set_at: nil,
        confirmed_at: now
      }
      |> Map.merge(Map.drop(attrs, [:role, :state]))

    user =
      %Ysc.Accounts.User{}
      |> Ysc.Accounts.User.registration_changeset(user_attrs)
      |> Ecto.Changeset.put_change(:post_migration_onboarding_completed_at, now)
      |> Ysc.Repo.insert!()

    apply_fixture_role_state(user, role, state)
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
