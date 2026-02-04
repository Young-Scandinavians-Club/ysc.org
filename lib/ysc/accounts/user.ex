defmodule Ysc.Accounts.User do
  @moduledoc """
  User schema and changesets.

  Defines the User database schema, validations, and changeset functions
  for user data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Extensions.PhoneNumber
  alias Ysc.Accounts.{Address, FamilyMember, SignupApplication, User}

  @derive {
    Flop.Schema,
    filterable: [
      :email,
      :first_name,
      :last_name,
      :phone_number,
      :state,
      :role,
      :board_position
    ],
    sortable: [:email, :first_name, :last_name, :state, :role],
    default_limit: 50,
    max_limit: 200,
    default_order: %{
      order_by: [:first_name, :last_name],
      order_directions: [:asc, :asc]
    }
  }

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true, default: nil
    field :confirmed_at, :utc_datetime

    field :state, UserAccountState
    field :role, UserAccountRole

    field :board_position, BoardMemberPosition

    field :first_name, :string, redact: true
    field :last_name, :string, redact: true
    field :phone_number, :string, redact: true
    field :date_of_birth, :date

    has_one :registration_form, SignupApplication
    has_one :billing_address, Address, foreign_key: :user_id
    has_many :family_members, FamilyMember, on_replace: :delete

    belongs_to :primary_user, User, foreign_key: :primary_user_id
    has_many :sub_accounts, User, foreign_key: :primary_user_id

    field :most_connected_country, :string
    field :lifetime_membership_awarded_at, :utc_datetime
    field :stripe_id, :string
    field :quickbooks_customer_id, :string

    # Notification preferences (email)
    field :newsletter_notifications, :boolean, default: true
    field :event_notifications, :boolean, default: true
    field :account_notifications, :boolean, default: true

    # SMS notification preferences
    field :account_notifications_sms, :boolean, default: true
    field :event_notifications_sms, :boolean, default: true

    has_one :default_membership_payment_method, Ysc.Payments.PaymentMethod,
      foreign_key: :user_id,
      where: [is_default: true]

    has_many :payment_methods, Ysc.Payments.PaymentMethod, foreign_key: :user_id

    has_many :subscriptions, Ysc.Subscriptions.Subscription,
      foreign_key: :user_id

    has_many :auth_events, Ysc.Accounts.AuthEvent

    has_many :expense_reports, Ysc.ExpenseReports.ExpenseReport,
      foreign_key: :user_id

    has_many :bank_accounts, Ysc.ExpenseReports.BankAccount,
      foreign_key: :user_id

    has_many :user_notes, Ysc.Accounts.UserNote, foreign_key: :user_id
    has_many :passkeys, Ysc.Accounts.UserPasskey, foreign_key: :user_id

    field :display_name, :string, virtual: true
    field :payment_id, :string, virtual: true
    field :sms_opt_in, :boolean, virtual: true

    # Verification timestamps
    field :email_verified_at, :utc_datetime
    field :phone_verified_at, :utc_datetime
    field :password_set_at, :utc_datetime
    field :passkey_prompt_dismissed_at, :utc_datetime

    timestamps()
  end

  @spec registration_changeset(
          {map(), map()}
          | %{
              :__struct__ =>
                atom() | %{:__changeset__ => map(), optional(any()) => any()},
              optional(atom()) => any()
            },
          :invalid
          | %{
              optional(:__struct__) => none(),
              optional(atom() | binary()) => any()
            }
        ) :: Ecto.Changeset.t()
  @doc """
  A user changeset for registration.

  It is important to validate the length of both email and password.
  Otherwise databases may truncate the email without warnings, which
  could lead to unpredictable or insecure behaviour. Long passwords may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.

    * `:validate_email` - Validates the uniqueness of the email, in case
      you don't want to validate the uniqueness of the email (like when
      using this changeset for validations on a LiveView form before
      submitting the form), this option can be set to `false`.
      Defaults to `true`.

    * `:require_password` - Requires password validation during registration.
      Defaults to `false` for application-only registration.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    require_password = Keyword.get(opts, :require_password, false)

    user
    |> cast(attrs, [
      :email,
      :password,
      :state,
      :role,
      :first_name,
      :last_name,
      :phone_number,
      :most_connected_country,
      :board_position,
      :sms_opt_in,
      :date_of_birth
    ])
    |> validate_length(:first_name, min: 1, max: 150)
    |> validate_length(:last_name, min: 1, max: 150)
    |> validate_required([:first_name, :last_name])
    |> validate_email(opts)
    |> validate_password_optional(opts, require_password)
    |> validate_phone_optional(opts)
    |> set_sms_notifications_from_opt_in(attrs)
    |> cast_assoc(:registration_form,
      with: &SignupApplication.application_changeset/2,
      opts: opts
    )
    |> copy_date_of_birth_from_application()
    |> cast_assoc(
      :family_members,
      with: &FamilyMember.family_member_changeset/2,
      sort_param: :family_members_order,
      drop_param: :family_members_delete,
      opts: opts
    )
  end

  @doc """
  A user changeset for sub-account registration via family invite.

  Similar to registration_changeset but:
  - Sets primary_user_id from invite
  - Sets state to :active (sub-accounts don't need approval)
  - Password is optional (can be set later)
  """
  def sub_account_registration_changeset(
        user,
        attrs,
        primary_user_id,
        opts \\ []
      ) do
    require_password = Keyword.get(opts, :require_password, false)

    user
    |> cast(attrs, [
      :email,
      :password,
      :first_name,
      :last_name,
      :phone_number,
      :most_connected_country,
      :sms_opt_in,
      :date_of_birth
    ])
    |> put_change(:primary_user_id, primary_user_id)
    |> put_change(:state, :active)
    |> validate_length(:first_name, min: 1, max: 150)
    |> validate_length(:last_name, min: 1, max: 150)
    |> validate_required([:first_name, :last_name, :date_of_birth])
    |> validate_email(opts)
    |> set_password_set_at_if_password_provided(opts)
    |> validate_password_optional(opts, require_password)
    |> validate_phone_optional(opts)
    |> set_sms_notifications_from_opt_in(attrs)
    |> validate_date_of_birth()
  end

  @spec update_user_changeset(
          {map(), map()}
          | %{
              :__struct__ =>
                atom() | %{:__changeset__ => map(), optional(any()) => any()},
              optional(atom()) => any()
            },
          :invalid
          | %{
              optional(:__struct__) => none(),
              optional(atom() | binary()) => any()
            }
        ) :: Ecto.Changeset.t()
  def update_user_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [
      :state,
      :role,
      :first_name,
      :last_name,
      :phone_number,
      :most_connected_country,
      :board_position,
      :stripe_id,
      :quickbooks_customer_id,
      :lifetime_membership_awarded_at,
      :date_of_birth,
      :passkey_prompt_dismissed_at
    ])
    |> validate_length(:first_name, min: 1, max: 150)
    |> validate_length(:last_name, min: 1, max: 150)
    |> validate_required([:first_name, :last_name])
    |> validate_phone_optional(opts)
    |> validate_date_of_birth()
  end

  @doc """
  A changeset for updating user and address information together.
  """
  def update_user_with_address_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [
      :state,
      :role,
      :first_name,
      :last_name,
      :phone_number,
      :most_connected_country,
      :board_position,
      :stripe_id,
      :quickbooks_customer_id,
      :lifetime_membership_awarded_at,
      :date_of_birth
    ])
    |> cast_assoc(:billing_address, with: &Address.changeset/2)
    |> validate_length(:first_name, min: 1, max: 150)
    |> validate_length(:last_name, min: 1, max: 150)
    |> validate_required([:first_name, :last_name])
    |> validate_phone(opts)
    |> validate_date_of_birth()
  end

  def update_user_state_changeset(user, attrs, _opts \\ []) do
    user |> cast(attrs, [:state])
  end

  @doc """
  A user changeset for updating profile information.
  """
  def profile_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [
      :first_name,
      :last_name,
      :phone_number,
      :most_connected_country
    ])
    |> validate_length(:first_name, min: 1, max: 150)
    |> validate_length(:last_name, min: 1, max: 150)
    |> validate_required([:first_name, :last_name])
    |> validate_phone(opts)
  end

  @doc """
  A user changeset for updating notification preferences.
  """
  def notification_preferences_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :newsletter_notifications,
      :event_notifications,
      :account_notifications,
      :account_notifications_sms,
      :event_notifications_sms
    ])
    |> validate_required([:account_notifications])
    |> validate_inclusion(:account_notifications, [true],
      message: "Account notifications cannot be disabled"
    )
  end

  defp validate_phone(changeset, _opts) do
    changeset
    |> validate_required([:phone_number])
    |> validate_length(:phone_number, max: 25)
    |> validate_maybe_accept_phone()
  end

  defp validate_phone_optional(changeset, _opts) do
    changeset
    |> validate_length(:phone_number, max: 25)
    |> validate_maybe_accept_phone_optional()
  end

  defp validate_maybe_accept_phone(changeset) do
    phone_number = get_change(changeset, :phone_number)

    if is_nil(phone_number) do
      changeset
    else
      with {:ok, phone_number} <- PhoneNumber.parse_phone_number(phone_number),
           true <- PhoneNumber.possible_phone_number?(phone_number),
           true <- PhoneNumber.valid_phone_number?(phone_number) do
        phone_number = PhoneNumber.format_phone_number(phone_number, :e164)
        put_change(changeset, :phone_number, phone_number)
      else
        {:error, message} ->
          add_error(changeset, :phone_number, message)

        _ ->
          add_error(
            changeset,
            :phone_number,
            "Sorry, that does not look like a valid phone number"
          )
      end
    end
  end

  defp validate_maybe_accept_phone_optional(changeset) do
    phone_number = get_change(changeset, :phone_number)

    if is_nil(phone_number) || phone_number == "" do
      changeset
    else
      with {:ok, phone_number} <- PhoneNumber.parse_phone_number(phone_number),
           true <- PhoneNumber.possible_phone_number?(phone_number),
           true <- PhoneNumber.valid_phone_number?(phone_number) do
        phone_number = PhoneNumber.format_phone_number(phone_number, :e164)
        put_change(changeset, :phone_number, phone_number)
      else
        {:error, message} ->
          add_error(changeset, :phone_number, message)

        _ ->
          add_error(
            changeset,
            :phone_number,
            "Sorry, that does not look like a valid phone number"
          )
      end
    end
  end

  defp set_sms_notifications_from_opt_in(changeset, attrs) do
    sms_opt_in = attrs["sms_opt_in"] == "true" || attrs[:sms_opt_in] == true

    if sms_opt_in do
      changeset
      |> put_change(:account_notifications_sms, true)
      |> put_change(:event_notifications_sms, true)
    else
      changeset
      |> put_change(:account_notifications_sms, false)
      |> put_change(:event_notifications_sms, false)
    end
  end

  defp set_password_set_at_if_password_provided(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    # Also check if hashed_password was set (password was already hashed in a previous step)
    hashed_password = get_change(changeset, :hashed_password)

    if hash_password? && (password || hashed_password) do
      # Only set password_set_at if it's not already set
      if get_field(changeset, :password_set_at) do
        changeset
      else
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        put_change(changeset, :password_set_at, now)
      end
    else
      changeset
    end
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp validate_password_optional(changeset, opts, require_password) do
    if require_password do
      validate_password(changeset, opts)
    else
      changeset
      |> validate_length(:password, min: 12, max: 72)
      |> maybe_hash_password(opts)
    end
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Argon, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Ysc.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = Timex.now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Argon2.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(
        %Ysc.Accounts.User{hashed_password: hashed_password},
        password
      )
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Argon2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  @doc """
  Changeset for marking email as verified.
  """
  def email_verification_changeset(user, attrs) do
    user
    |> cast(attrs, [:email_verified_at])
    |> validate_required([:email_verified_at])
  end

  @doc """
  Changeset for marking phone as verified.
  """
  def phone_verification_changeset(user, attrs) do
    user
    |> cast(attrs, [:phone_verified_at])
    |> validate_required([:phone_verified_at])
  end

  @doc """
  Changeset for marking password as set.
  """
  def password_set_changeset(user, attrs) do
    user
    |> cast(attrs, [:password_set_at])
    |> validate_required([:password_set_at])
  end

  defp copy_date_of_birth_from_application(changeset) do
    # If date_of_birth is not directly set, try to get it from the nested registration_form
    case get_change(changeset, :date_of_birth) do
      nil ->
        # Try to get birth_date from the nested registration_form changeset
        registration_form_changeset = get_change(changeset, :registration_form)

        case registration_form_changeset do
          %Ecto.Changeset{changes: %{birth_date: birth_date}}
          when not is_nil(birth_date) ->
            put_change(changeset, :date_of_birth, birth_date)

          %Ecto.Changeset{data: %{birth_date: birth_date}}
          when not is_nil(birth_date) ->
            put_change(changeset, :date_of_birth, birth_date)

          _ ->
            changeset
        end

      _ ->
        changeset
    end
  end

  defp validate_date_of_birth(changeset) do
    date_of_birth =
      get_change(changeset, :date_of_birth) ||
        get_field(changeset, :date_of_birth)

    cond do
      is_nil(date_of_birth) ->
        changeset

      Date.compare(date_of_birth, ~D[1900-01-01]) == :lt ->
        add_error(changeset, :date_of_birth, "must be after 1900")

      Date.compare(date_of_birth, Date.utc_today()) == :gt ->
        add_error(changeset, :date_of_birth, "cannot be in the future")

      true ->
        changeset
    end
  end

  @doc """
  Returns the provider_id of the default payment method.
  """
  def payment_id(%__MODULE__{} = user) do
    case Ysc.Payments.get_default_payment_method(user) do
      %{provider_id: provider_id} -> provider_id
      nil -> nil
    end
  end

  @doc """
  Populates virtual fields on a user struct.
  This should be called after preloading associations.
  """
  def populate_virtual_fields(%__MODULE__{} = user) do
    user
    |> Map.put(:payment_id, payment_id(user))
  end
end
