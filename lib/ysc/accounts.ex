defmodule Ysc.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false

  alias Ysc.Accounts.UserEvent
  alias Ysc.Accounts.SignupApplicationEvent
  alias YscWeb.Authorization.Policy
  alias Ysc.Accounts.SignupApplication
  alias Ysc.Repo

  alias Ysc.Accounts.{
    Address,
    User,
    UserToken,
    UserNotifier,
    AuthService,
    UserNote,
    UserPasskey
  }

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by phone number.

  Handles various phone number formats by normalizing to E.164 format
  before searching. Tries multiple normalization strategies to match
  phone numbers with or without country codes, with various formatting.

  ## Examples

      iex> get_user_by_phone_number("+12065551234")
      %User{}

      iex> get_user_by_phone_number("206-555-1234")
      %User{}

      iex> get_user_by_phone_number("unknown")
      nil

  """
  def get_user_by_phone_number(phone_number) when is_binary(phone_number) do
    # Try exact match first (fastest)
    case Repo.get_by(User, phone_number: phone_number) do
      nil -> find_user_by_normalized_phone(phone_number)
      user -> user
    end
  end

  # Try to find user by normalizing the phone number to various formats
  defp find_user_by_normalized_phone(phone_number) do
    # Try to normalize to E.164 format
    normalized_numbers = normalize_phone_number_variants(phone_number)

    # Try each normalized variant
    Enum.reduce_while(normalized_numbers, nil, fn normalized, _acc ->
      case Repo.get_by(User, phone_number: normalized) do
        nil -> {:cont, nil}
        user -> {:halt, user}
      end
    end)
  end

  # Normalize phone number to multiple possible E.164 formats
  defp normalize_phone_number_variants(phone_number) do
    # Common Nordic countries and US (based on YSC's focus)
    default_countries = ["US", "SE", "NO", "DK", "FI", "IS"]

    # Try parsing with no country code first (uses number as-is)
    variants =
      case normalize_to_e164(phone_number, nil) do
        {:ok, normalized} -> [normalized]
        {:error, _} -> []
      end

    # Try with each default country
    variants =
      Enum.reduce(default_countries, variants, fn country, acc ->
        case normalize_to_e164(phone_number, country) do
          {:ok, normalized} -> [normalized | acc]
          {:error, _} -> acc
        end
      end)

    # Remove duplicates and return
    Enum.uniq(variants)
  end

  # Normalize phone number to E.164 format
  defp normalize_to_e164(phone_number, country_code) do
    try do
      # Remove common formatting characters but keep + and digits
      cleaned = String.replace(phone_number, ~r/[^\d+]/, "")

      case ExPhoneNumber.parse(cleaned, country_code) do
        {:ok, parsed} ->
          if ExPhoneNumber.is_valid_number?(parsed) do
            {:ok, ExPhoneNumber.format(parsed, :e164)}
          else
            {:error, :invalid_number}
          end

        {:error, _} ->
          {:error, :parse_failed}
      end
    rescue
      _ -> {:error, :normalization_failed}
    end
  end

  @spec get_user_by_email_and_password(binary(), binary()) :: any()
  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id, preloads \\ []) do
    Repo.get!(User, id) |> Repo.preload(preloads)
  end

  @doc """
  Gets a single user, returns nil if not found.

  ## Examples

      iex> get_user(123)
      %User{}

      iex> get_user(456)
      nil

  """
  def get_user(id, preloads \\ []) do
    case Repo.get(User, id) do
      nil -> nil
      user -> Repo.preload(user, preloads)
    end
  end

  def get_user_from_stripe_id(stripe_id) do
    Repo.get_by(User, stripe_id: stripe_id)
  end

  ## Passkey functions

  @doc """
  Gets all passkeys for a user.
  """
  def get_user_passkeys(user) do
    from(p in UserPasskey,
      where: p.user_id == ^user.id,
      order_by: [desc: p.last_used_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a user passkey by external_id (credential ID).
  """
  def get_user_passkey_by_external_id(external_id) do
    Repo.get_by(UserPasskey, external_id: external_id)
  end

  @doc """
  Gets a user by email with passkeys preloaded.
  """
  def get_user_by_email_for_passkey(email) when is_binary(email) do
    case Repo.get_by(User, email: email) do
      nil -> nil
      user -> Repo.preload(user, :passkeys)
    end
  end

  @doc """
  Creates a new user passkey.
  """
  def create_user_passkey(user, attrs) do
    %UserPasskey{}
    |> UserPasskey.create_changeset(Map.merge(attrs, %{user_id: user.id}))
    |> Repo.insert()
  end

  @doc """
  Updates the sign_count and last_used_at for a passkey.
  """
  def update_passkey_sign_count(passkey, sign_count) do
    passkey
    |> UserPasskey.update_usage_changeset(%{
      sign_count: sign_count,
      last_used_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Deletes a user passkey.
  """
  def delete_user_passkey(passkey) do
    Repo.delete(passkey)
  end

  @doc """
  Checks if the passkey prompt should be shown to a user.

  Returns true if:
  - User has no passkeys
  - Either passkey_prompt_dismissed_at is nil OR it's been more than 30 days since dismissal
  """
  def should_show_passkey_prompt?(user) do
    # Check if user has any passkeys
    passkeys = get_user_passkeys(user)

    if Enum.empty?(passkeys) do
      # User has no passkeys, check dismissal status
      if is_nil(user.passkey_prompt_dismissed_at) do
        # Never dismissed, show prompt
        true
      else
        # Check if 30 days have passed since dismissal
        days_since_dismissal =
          DateTime.diff(
            DateTime.utc_now(),
            user.passkey_prompt_dismissed_at,
            :day
          )

        days_since_dismissal >= 30
      end
    else
      # User has passkeys, don't show prompt
      false
    end
  end

  @doc """
  Dismisses the passkey prompt for a user by setting passkey_prompt_dismissed_at to current time.
  """
  def dismiss_passkey_prompt(user) do
    user
    |> User.update_user_changeset(%{
      passkey_prompt_dismissed_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Searches for users by name or email.

  Returns a list of active users matching the search query.
  The search is case-insensitive and matches partial strings
  in first_name, last_name, or email fields.

  ## Options
    - `:limit` - Maximum number of results (default: 10)
    - `:state` - User state to filter by (default: :active)

  ## Examples

      iex> search_users("john")
      [%User{first_name: "John", ...}, %User{last_name: "Johnson", ...}]

      iex> search_users("john@example.com")
      [%User{email: "john@example.com", ...}]

  """
  def search_users(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 10)
    state = Keyword.get(opts, :state, :active)
    search_term = "%#{query}%"

    from(u in User,
      where: u.state == ^state,
      where:
        ilike(u.first_name, ^search_term) or
          ilike(u.last_name, ^search_term) or
          ilike(u.email, ^search_term) or
          ilike(
            fragment("? || ' ' || ?", u.first_name, u.last_name),
            ^search_term
          ),
      order_by: [asc: u.last_name, asc: u.first_name],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Checks if a user has an active membership.
  Includes lifetime membership which never expires.

  For sub-accounts, checks the primary user's membership.
  """
  def has_active_membership?(user) do
    # If user is a sub-account, check primary user's membership
    if sub_account?(user) do
      primary_user = get_primary_user(user)
      if primary_user, do: has_active_membership?(primary_user), else: false
    else
      check_primary_user_membership(user)
    end
  end

  defp check_primary_user_membership(user) do
    # Check for lifetime membership first
    if has_lifetime_membership?(user) do
      true
    else
      # Get all subscriptions for the user and check if any are valid (active or trialing)
      check_user_subscriptions(user)
    end
  end

  defp check_user_subscriptions(user) do
    case user.subscriptions do
      %Ecto.Association.NotLoaded{} ->
        # If subscriptions aren't loaded, fetch them
        user_with_subscriptions = get_user!(user.id, [:subscriptions])

        user_with_subscriptions.subscriptions
        |> Enum.any?(&Ysc.Subscriptions.valid?/1)

      subscriptions when is_list(subscriptions) ->
        subscriptions
        |> Enum.any?(&Ysc.Subscriptions.valid?/1)

      _ ->
        false
    end
  end

  @doc """
  Checks if a user has a lifetime membership.
  """
  def has_lifetime_membership?(user) do
    not is_nil(user.lifetime_membership_awarded_at)
  end

  def get_signup_application_from_user_id!(id, current_user, preloads \\ []) do
    with :ok <-
           Policy.authorize(:signup_application_read, current_user, %{
             user_id: id
           }) do
      Repo.get_by!(SignupApplication, user_id: id)
      |> Repo.preload(preloads)
    end
  end

  ## User registration

  @spec register_user(
          :invalid
          | %{
              optional(:__struct__) => none(),
              optional(atom() | binary()) => any()
            }
        ) :: any()
  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    Repo.transaction(fn ->
      case %User{}
           |> User.registration_changeset(attrs, require_password: false)
           |> Repo.insert() do
        {:ok, user} ->
          # Preload registration_form within the same transaction
          # This ensures the association is available immediately after insert
          user = Repo.preload(user, :registration_form)

          # Copy date_of_birth from registration_form if not already set
          user =
            if is_nil(user.date_of_birth) && user.registration_form &&
                 user.registration_form.birth_date do
              case user
                   |> User.update_user_changeset(%{
                     date_of_birth: user.registration_form.birth_date
                   })
                   |> Repo.update() do
                {:ok, updated_user} -> updated_user
                {:error, _} -> user
              end
            else
              user
            end

          # Create billing address from signup application
          # This happens within the same transaction, so registration_form is guaranteed to be available
          case create_billing_address_from_signup(user) do
            {:ok, _address} ->
              :ok

            {:error, changeset} ->
              # Log the error but don't fail registration
              require Logger

              Logger.warning(
                "Failed to create billing address during registration",
                user_id: user.id,
                errors: inspect(changeset.errors)
              )
          end

          # Return user for use after transaction
          user

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, user} ->
        is_test = Ysc.Env.test?()

        # In tests, avoid spawning background tasks that touch the DB inside the SQL sandbox,
        # as they can produce noisy DBConnection ownership/disconnect logs.
        unless is_test do
          Task.start(fn ->
            try do
              Ysc.Customers.create_stripe_customer(user)
            rescue
              e ->
                require Logger

                Logger.warning(
                  "Failed to create Stripe customer in background task",
                  user_id: user.id,
                  error: Exception.format(:error, e, __STACKTRACE__)
                )
            catch
              kind, reason ->
                require Logger

                Logger.warning(
                  "Failed to create Stripe customer in background task",
                  user_id: user.id,
                  kind: kind,
                  reason: inspect(reason)
                )
            end
          end)
        end

        subscribe_user_to_newsletter(user)
        {:ok, user}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        # If reason is not a changeset (shouldn't happen, but handle it)
        {:error, reason}
    end
  end

  defp create_billing_address_from_signup(user) do
    # Check if registration_form is loaded and available
    cond do
      # Association is loaded and has data
      Ecto.assoc_loaded?(user.registration_form) &&
          user.registration_form != nil ->
        signup_application = user.registration_form

        # Check if address already exists
        existing_address = Repo.get_by(Address, user_id: user.id)

        if existing_address do
          {:ok, existing_address}
        else
          # Only create address if we have the required fields
          if has_required_address_fields?(signup_application) do
            # Include user_id in the attrs so it's validated properly
            address_attrs = %{
              address: signup_application.address,
              city: signup_application.city,
              region: signup_application.region,
              postal_code: signup_application.postal_code,
              country: signup_application.country,
              user_id: user.id
            }

            changeset = Address.changeset(%Address{}, address_attrs)

            case Repo.insert(changeset) do
              {:ok, address} ->
                {:ok, address}

              {:error, changeset} ->
                {:error, changeset}
            end
          else
            require Logger

            Logger.warning(
              "Skipping billing address creation - missing required fields",
              user_id: user.id,
              has_address: !is_nil(signup_application.address),
              has_city: !is_nil(signup_application.city),
              has_postal_code: !is_nil(signup_application.postal_code),
              has_country: !is_nil(signup_application.country)
            )

            {:ok, nil}
          end
        end

      # Association not loaded - try to load it
      not Ecto.assoc_loaded?(user.registration_form) ->
        # Try to load the registration form
        user_with_form = Repo.preload(user, :registration_form)

        if user_with_form.registration_form do
          create_billing_address_from_signup(user_with_form)
        else
          require Logger

          Logger.warning(
            "Skipping billing address creation - registration_form not found",
            user_id: user.id
          )

          {:ok, nil}
        end

      # Association loaded but nil
      true ->
        require Logger

        Logger.warning(
          "Skipping billing address creation - registration_form is nil",
          user_id: user.id
        )

        {:ok, nil}
    end
  end

  defp has_required_address_fields?(signup_application) do
    signup_application.address &&
      signup_application.city &&
      signup_application.postal_code &&
      signup_application.country
  end

  defp subscribe_user_to_newsletter(user) do
    # Subscribe user to Keila newsletter asynchronously via Oban
    # Failures are logged but don't affect user registration

    # Build custom metadata
    metadata = %{
      "user_id" => user.id,
      "signup_date" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "role" => to_string(user.role || "member"),
      "state" => to_string(user.state || "active")
    }

    # Build job args with all available user data
    job_args = %{
      "email" => user.email,
      "action" => "subscribe",
      "first_name" => user.first_name,
      "last_name" => user.last_name,
      "data" => metadata
    }

    case job_args
         |> YscWeb.Workers.KeilaSubscriber.new()
         |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, changeset} ->
        require Logger

        Logger.warning("Failed to enqueue Keila subscription job",
          user_id: user.id,
          email: user.email,
          errors: inspect(changeset.errors)
        )

        :ok
    end
  end

  @doc """
  Updates newsletter subscription when user changes email.
  Only subscribes the new email if user has newsletter_notifications enabled.
  Unsubscribes the old email.
  """
  def update_newsletter_on_email_change(user, old_email, new_email) do
    require Logger

    # Unsubscribe old email
    case %{"email" => old_email, "action" => "unsubscribe"}
         |> YscWeb.Workers.KeilaSubscriber.new()
         |> Oban.insert() do
      {:ok, _job} ->
        Logger.debug("Enqueued newsletter unsubscription for old email",
          user_id: user.id,
          old_email: old_email
        )

      {:error, changeset} ->
        Logger.warning(
          "Failed to enqueue newsletter unsubscription for old email",
          user_id: user.id,
          old_email: old_email,
          errors: inspect(changeset.errors)
        )
    end

    # Subscribe new email only if user has newsletter_notifications enabled
    if user.newsletter_notifications do
      metadata = %{
        "user_id" => user.id,
        "email_changed_date" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "role" => to_string(user.role || "member"),
        "state" => to_string(user.state || "active")
      }

      job_args = %{
        "email" => new_email,
        "action" => "subscribe",
        "first_name" => user.first_name,
        "last_name" => user.last_name,
        "data" => metadata
      }

      case job_args
           |> YscWeb.Workers.KeilaSubscriber.new()
           |> Oban.insert() do
        {:ok, _job} ->
          Logger.debug("Enqueued newsletter subscription for new email",
            user_id: user.id,
            new_email: new_email
          )

          :ok

        {:error, changeset} ->
          Logger.warning(
            "Failed to enqueue newsletter subscription for new email",
            user_id: user.id,
            new_email: new_email,
            errors: inspect(changeset.errors)
          )

          :ok
      end
    else
      Logger.debug(
        "Skipping newsletter subscription for new email (notifications disabled)",
        user_id: user.id,
        new_email: new_email
      )

      :ok
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs,
      hash_password: false,
      validate_email: true
    )
  end

  @doc """
  Updates user phone number and SMS preferences.
  """
  def update_user_phone_and_sms(user, attrs) do
    with {:ok, updated_user} <-
           user
           |> User.registration_changeset(attrs,
             hash_password: false,
             validate_email: false
           )
           |> Repo.update() do
      # Update Stripe customer with new phone information
      Task.start(fn ->
        Ysc.Customers.update_stripe_customer(updated_user)
      end)

      {:ok, updated_user}
    end
  end

  @doc """
  Generates a 6-digit verification code for email verification during account setup.
  """
  def generate_email_verification_code do
    # Generate a random 6-digit code
    :rand.uniform(999_999)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  @doc """
  Stores an email verification code for a user with expiration.

  ## Parameters
  - user: The user struct
  - code: The verification code
  - expires_in_seconds: How long until expiration (default: 600 = 10 minutes)

  Returns :ok on success
  """
  def store_email_verification_code(user, code, expires_in_seconds \\ 600) do
    Ysc.VerificationCache.store_code(
      user.id,
      :email_verification,
      code,
      expires_in_seconds
    )
  end

  @doc """
  Stores a phone verification code for a user.
  """
  def store_phone_verification_code(user, code, expires_in_seconds \\ 600) do
    Ysc.VerificationCache.store_code(
      user.id,
      :phone_verification,
      code,
      expires_in_seconds
    )
  end

  @doc """
  Verifies an email verification code for a user.

  Returns {:ok, :verified} if the code is valid and matches,
  {:error, :not_found} if no code exists,
  {:error, :expired} if the code has expired,
  {:error, :invalid_code} if the code doesn't match.
  """
  def verify_email_verification_code(user, provided_code) do
    # In dev/test environments, accept "000000" as a valid code
    if dev_or_sandbox?() and provided_code == "000000" do
      {:ok, :verified}
    else
      Ysc.VerificationCache.verify_code(
        user.id,
        :email_verification,
        provided_code
      )
    end
  end

  @doc """
  Retrieves the current email verification code for a user if it exists and hasn't expired.

  Returns {:ok, code} if found and valid, {:error, reason} otherwise.
  """
  def get_email_verification_code(user) do
    case Ysc.VerificationCache.get_code(user.id, :email_verification) do
      {:ok, code} -> code
      {:error, _} -> nil
    end
  end

  @doc """
  Removes the email verification code for a user (useful for cleanup).
  """
  def remove_email_verification_code(user) do
    Ysc.VerificationCache.remove_code(user.id, :email_verification)
  end

  @doc """
  Generates and stores an email verification code for a user.

  This is a convenience function that generates a code and stores it in the cache.

  Returns the generated code.
  """
  def generate_and_store_email_verification_code(
        user,
        expires_in_seconds \\ 600
      ) do
    code = generate_email_verification_code()
    :ok = store_email_verification_code(user, code, expires_in_seconds)
    code
  end

  @doc """
  Sends an email verification code to the user.
  """
  def send_email_verification_code(
        user,
        code,
        resend_key_suffix \\ nil,
        target_email \\ nil
      ) do
    # Use target_email if provided, otherwise use user's email
    email_address = target_email || user.email

    # Include resend suffix in idempotency key to allow multiple sends
    suffix = if resend_key_suffix, do: "_#{resend_key_suffix}", else: ""
    idempotency_key = "account_setup_verification_#{user.id}#{suffix}"

    YscWeb.Emails.Notifier.schedule_email(
      email_address,
      idempotency_key,
      "Verify Your Email Address - YSC",
      "account_setup_verification",
      %{
        first_name: user.first_name,
        verification_code: code
      },
      """
      ==============================

      Hi #{String.capitalize(user.first_name)},

      Your verification code is: #{code}

      This code will expire in 10 minutes.

      ==============================
      """,
      user.id
    )
  end

  @doc """
  Verifies an email verification code for account setup.
  For now, this is a simple implementation - in production you'd want to store
  codes with expiration times in a more secure way.
  """
  def verify_email_code(user, code) do
    # For now, we'll just accept any 6-digit code as valid
    # In production, you'd store the code with expiration and validate it properly
    if String.length(code) == 6 && String.match?(code, ~r/^\d{6}$/) do
      {:ok, user}
    else
      {:error, :invalid_code}
    end
  end

  @doc """
  Generates and stores a phone verification code for a user.

  This is a convenience function that generates a code and stores it in the cache.

  Returns the generated code.
  """
  def generate_and_store_phone_verification_code(
        user,
        expires_in_seconds \\ 600
      ) do
    # Reuse the same code generation
    code = generate_email_verification_code()
    :ok = store_phone_verification_code(user, code, expires_in_seconds)
    code
  end

  @doc """
  Sends a phone verification code via SMS.
  """
  def send_phone_verification_code(user, code, resend_key_suffix \\ nil) do
    # Include resend suffix in idempotency key to allow multiple sends
    suffix = if resend_key_suffix, do: "_#{resend_key_suffix}", else: ""
    idempotency_key = "phone_verification_#{user.id}#{suffix}"

    YscWeb.Sms.Notifier.schedule_sms(
      user.phone_number,
      idempotency_key,
      "phone_verification",
      YscWeb.Sms.PhoneVerification.prepare_sms_data(user, code),
      user.id
    )
  end

  @doc """
  Verifies a phone verification code for a user.

  Returns {:ok, :verified} if the code is valid and matches,
  {:error, :not_found} if no code exists,
  {:error, :expired} if the code has expired,
  {:error, :invalid_code} if the code doesn't match.
  """
  def verify_phone_verification_code(user, provided_code) do
    # In dev/test environments, accept "000000" as a valid code
    if dev_or_sandbox?() and provided_code == "000000" do
      {:ok, :verified}
    else
      Ysc.VerificationCache.verify_code(
        user.id,
        :phone_verification,
        provided_code
      )
    end
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  def list_bod_members() do
    from(u in User,
      where: not is_nil(u.board_position),
      select: %{
        id: u.id,
        email: u.email,
        first_name: u.first_name,
        last_name: u.last_name,
        board_position: u.board_position,
        most_connected_country: u.most_connected_country
      },
      order_by: [
        desc: fragment("CASE
          WHEN board_position = 'president' THEN 10
          WHEN board_position = 'vice_president' THEN 9
          WHEN board_position = 'secretary' THEN 8
          WHEN board_position = 'treasurer' THEN 7
          WHEN board_position = 'clear_lake_cabin_master' THEN 6
          WHEN board_position = 'tahoe_cabin_master' THEN 5
          WHEN board_position = 'event_director' THEN 4
          WHEN board_position = 'member_outreach' THEN 3
          WHEN board_position = 'membership_director' THEN 2
          ELSE 1
        END")
      ]
    )
    |> Repo.all()
  end

  @doc """
  Gets all users that have signed up and need their application reviewed.
  These are users with pending_approval state.
  """
  def get_pending_approval_users() do
    Repo.all(
      from u in User,
        where: u.state == :pending_approval,
        preload: [:registration_form],
        order_by: [asc: u.inserted_at]
    )
  end

  def list_paginated_users(params) do
    # Extract membership_type filter if present
    {membership_filters, other_params} = extract_membership_filters(params)
    # Check if sorting by membership_type
    {membership_sort, other_params} = extract_membership_sort(other_params)

    base_query = from(u in User, where: u.state != :deleted)

    case Flop.validate_and_run(base_query, other_params, for: User) do
      {:ok, {users, meta}} ->
        # Apply membership filters if any
        filtered_users = apply_membership_filters(users, membership_filters)
        # Preload active subscriptions after the main query
        users_with_subscriptions = preload_active_subscriptions(filtered_users)
        # Apply membership sorting if needed
        sorted_users =
          apply_membership_sorting(users_with_subscriptions, membership_sort)

        {:ok, {sorted_users, meta}}

      error ->
        error
    end
  end

  defp fuzzy_search_user(search_term) do
    phone_like = "%#{search_term}%"

    from(u in User,
      where:
        u.state != :deleted and
          (fragment("SIMILARITY(?, ?) > 0.2", u.email, ^search_term) or
             fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^search_term) or
             fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^search_term) or
             ilike(u.phone_number, ^phone_like))
    )
  end

  def list_paginated_users(params, nil), do: list_paginated_users(params)

  def list_paginated_users(params, search_term) when search_term == "",
    do: list_paginated_users(params)

  @spec list_paginated_users(
          %{
            optional(:__struct__) => Flop,
            optional(atom() | binary()) => any()
          },
          any()
        ) :: {:error, Flop.Meta.t()} | {:ok, {list(), Flop.Meta.t()}}
  def list_paginated_users(params, search_term) do
    # Extract membership_type filter if present
    {membership_filters, other_params} = extract_membership_filters(params)
    # Check if sorting by membership_type
    {membership_sort, other_params} = extract_membership_sort(other_params)

    case Flop.validate_and_run(fuzzy_search_user(search_term), other_params,
           for: User
         ) do
      {:ok, {users, meta}} ->
        # Apply membership filters if any
        filtered_users = apply_membership_filters(users, membership_filters)
        # Preload active subscriptions after the main query
        users_with_subscriptions = preload_active_subscriptions(filtered_users)
        # Apply membership sorting if needed
        sorted_users =
          apply_membership_sorting(users_with_subscriptions, membership_sort)

        {:ok, {sorted_users, meta}}

      error ->
        error
    end
  end

  def update_user(user, params, %User{} = current_user) do
    with :ok <- Policy.authorize(:user_update, current_user, user),
         {:ok, updated_user} <-
           user |> User.update_user_changeset(params) |> Repo.update() do
      # Update Stripe customer with new information
      Task.start(fn ->
        Ysc.Customers.update_stripe_customer(updated_user)
      end)

      {:ok, updated_user}
    end
  end

  @doc """
  Updates user and their billing address information.
  """
  def update_user_with_address(user, params, %User{} = current_user) do
    with :ok <- Policy.authorize(:user_update, current_user, user),
         {:ok, updated_user} <-
           user
           |> User.update_user_with_address_changeset(params)
           |> Repo.update() do
      # Update Stripe customer with new information
      Task.start(fn ->
        Ysc.Customers.update_stripe_customer(updated_user)
      end)

      {:ok, updated_user}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user profile.
  """
  def change_user_profile(user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates the user profile information.
  """
  def update_user_profile(user, attrs) do
    with {:ok, updated_user} <-
           user |> User.profile_changeset(attrs) |> Repo.update() do
      # Update Stripe customer with new information
      Task.start(fn ->
        Ysc.Customers.update_stripe_customer(updated_user)
      end)

      {:ok, updated_user}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing notification preferences.
  """
  def change_notification_preferences(user, attrs \\ %{}) do
    User.notification_preferences_changeset(user, attrs)
  end

  @doc """
  Updates the user notification preferences.
  """
  def update_notification_preferences(user, attrs) do
    user
    |> User.notification_preferences_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user's billing address.
  """
  def change_billing_address(user, attrs \\ %{}) do
    address = get_or_build_billing_address(user)
    # Ensure all keys are strings to match form params
    attrs_with_user_id = Map.merge(attrs, %{"user_id" => user.id})
    Address.changeset(address, attrs_with_user_id)
  end

  @doc """
  Updates the user's billing address.
  """
  def update_billing_address(user, attrs) do
    address = get_or_build_billing_address(user)
    # Ensure all keys are strings to match form params
    attrs_with_user_id = Map.merge(attrs, %{"user_id" => user.id})

    with {:ok, _address} <-
           address
           |> Address.changeset(attrs_with_user_id)
           |> Repo.insert_or_update() do
      # Reload user with updated billing address and update Stripe customer
      updated_user = get_user!(user.id, [:billing_address])

      Task.start(fn ->
        Ysc.Customers.update_stripe_customer(updated_user)
      end)

      {:ok, updated_user}
    end
  end

  def get_billing_address(user) do
    case Repo.preload(user, :billing_address) do
      %{billing_address: %Address{} = address} -> address
      _ -> nil
    end
  end

  defp get_or_build_billing_address(user) do
    case Repo.preload(user, :billing_address) do
      %{billing_address: %Address{} = address} -> address
      _ -> %Address{}
    end
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <-
           UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, %{user: updated_user}} <-
           Repo.transaction(user_email_multi(user, email, context)),
         reloaded_user <- Repo.get!(User, updated_user.id) do
      # Update Stripe customer with new email
      Task.start(fn ->
        Ysc.Customers.update_stripe_customer(reloaded_user)
      end)

      {:ok, reloaded_user, email}
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, [context])
    )
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1})")
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(
        %User{} = user,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} =
      UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)

    UserNotifier.deliver_update_email_instructions(
      user,
      update_email_url_fun.(encoded_token)
    )

    {:ok, %{to: user.email, text_body: encoded_token}}
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  def update_default_payment_method(user, payment_method_id) do
    payment_method = Ysc.Payments.get_payment_method!(payment_method_id)
    Ysc.Payments.set_default_payment_method(user, payment_method)
  end

  @doc """
  Sets the initial password for a user during account setup.

  This is used when a user doesn't have a password yet and is setting one for the first time.
  Unlike update_user_password, this doesn't validate a current password.
  """
  def set_user_initial_password(user, attrs) do
    changeset = User.password_changeset(user, attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.run(:mark_password_set, fn _repo, %{user: updated_user} ->
      mark_password_set(updated_user)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :mark_password_set, changeset, _} -> {:error, changeset}
    end
  end

  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, :all)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    user = Repo.one(query)

    if user do
      # Check membership cache first - if we have cached membership data, we can skip
      # subscription preload to reduce DB queries. The membership cache will load
      # subscriptions on-demand if needed (when cache misses or expires).
      #
      # Note: This means subscriptions may not be preloaded on the user object.
      # Code that needs subscriptions should check Ecto.assoc_loaded?/1 or use
      # the membership cache functions which handle this automatically.
      cache_key = "membership:#{user.id}:active"

      case :ysc_cache |> Cachex.get(cache_key) do
        {:ok, nil} ->
          # Cache miss - preload subscriptions for membership check and other uses
          preload_active_subscriptions_for_auth(user)

        {:ok, _cached_membership} ->
          # Cache hit - skip preload to reduce DB queries
          # Subscriptions will be loaded by membership cache if needed
          user

        {:error, _reason} ->
          # Cache error - fallback to preloading for safety
          preload_active_subscriptions_for_auth(user)
      end
    else
      nil
    end
  end

  # Optimized preload that only fetches active subscriptions with subscription_items
  # This reduces queries from 2+ (user + all subscriptions) to 1 (user + active subscriptions)
  defp preload_active_subscriptions_for_auth(user) do
    active_subscriptions =
      from(s in Ysc.Subscriptions.Subscription,
        where: s.user_id == ^user.id,
        where: s.stripe_status in ["active", "trialing"],
        preload: [:subscription_items]
      )
      |> Repo.all()

    %{user | subscriptions: active_subscriptions}
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(
        %User{} = user,
        confirmation_url_fun
      )
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      UserNotifier.deliver_confirmation_instructions(
        user,
        confirmation_url_fun.(encoded_token)
      )

      {:ok, %{to: user.email, text_body: encoded_token}}
    end
  end

  def deliver_application_submitted_notification(%User{} = user) do
    YscWeb.Emails.Notifier.schedule_email(
      user.email,
      "#{user.id}",
      "Your Young Scandinavians Club application is in! 🎉",
      "application_submitted",
      %{first_name: String.capitalize(user.first_name)},
      """
      ==============================

      Hi #{String.capitalize(user.first_name)},

      Your application has been submitted! 🎉

      We'll review your application and get back to you soon.

      In the meantime, check out our upcoming events and latest news on our website.

      ==============================
      """,
      user.id
    )
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, ["confirm"])
    )
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset-password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(
        %User{} = user,
        reset_password_url_fun
      )
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} =
      UserToken.build_email_token(user, "reset_password")

    Repo.insert!(user_token)

    UserNotifier.deliver_reset_password_instructions(
      user,
      reset_password_url_fun.(encoded_token)
    )

    {:ok, %{to: user.email, text_body: encoded_token}}
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <-
           UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, :all)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  def get_signup_application_submission_date(user_id) do
    from(s in SignupApplication,
      select: %{submit_date: s.completed, timezone: s.browser_timezone},
      where: s.user_id == ^user_id
    )
    |> Repo.one()
  end

  def record_application_outcome(:approved, user, application, current_user) do
    with :ok <-
           Policy.authorize(:signup_application_update, current_user, %{
             user_id: user.id
           }) do
      with :ok <-
             Policy.authorize(:user_update, current_user, %{user_id: user.id}) do
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :user,
          User.update_user_changeset(user, %{
            state: :active,
            date_of_birth: application.birth_date
          })
        )
        |> Ecto.Multi.update(
          :application,
          SignupApplication.review_outcome_changeset(application, %{
            reviewed_at: DateTime.utc_now(),
            review_outcome: :approved,
            reviewed_by_user_id: current_user.id
          })
        )
        |> Ecto.Multi.insert(
          :application_event,
          SignupApplicationEvent.new_event_changeset(
            %SignupApplicationEvent{},
            %{
              event: :review_completed,
              application_id: application.id,
              user_id: user.id,
              reviewer_user_id: current_user.id,
              result: "approved"
            }
          )
        )
        |> Ecto.Multi.insert(
          :user_event,
          UserEvent.new_user_event_changeset(
            %UserEvent{},
            %{
              user_id: user.id,
              updated_by_user_id: current_user.id,
              type: :state_update,
              from: "#{user.state}",
              to: "active"
            }
          )
        )
        |> Repo.transaction()
        |> case do
          {:ok, _} -> :ok
          {:error, _, changeset, _} -> {:error, changeset}
        end
      end
    end
  end

  def record_application_outcome(:rejected, user, application, current_user) do
    with :ok <-
           Policy.authorize(:signup_application_update, current_user, %{
             user_id: user.id
           }) do
      with :ok <-
             Policy.authorize(:user_update, current_user, %{user_id: user.id}) do
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :user,
          User.update_user_state_changeset(user, %{state: :rejected})
        )
        |> Ecto.Multi.update(
          :application,
          SignupApplication.review_outcome_changeset(application, %{
            reviewed_at: DateTime.utc_now(),
            review_outcome: :rejected,
            reviewed_by_user_id: current_user.id
          })
        )
        |> Ecto.Multi.insert(
          :application_event,
          SignupApplicationEvent.new_event_changeset(
            %SignupApplicationEvent{},
            %{
              event: :review_completed,
              application_id: application.id,
              user_id: user.id,
              reviewer_user_id: current_user.id,
              result: "rejected"
            }
          )
        )
        |> Ecto.Multi.insert(
          :user_event,
          UserEvent.new_user_event_changeset(
            %UserEvent{},
            %{
              user_id: user.id,
              updated_by_user_id: current_user.id,
              type: :state_update,
              from: "#{user.state}",
              to: "rejected"
            }
          )
        )
        |> Repo.transaction()
        |> case do
          {:ok, _} -> :ok
          {:error, _, changeset, _} -> {:error, changeset}
        end
      end
    end
  end

  ## Authentication Events

  @doc """
  Gets the datetime of the last successful login for a user.
  Returns nil if no successful login is found.
  """
  def get_last_successful_login_datetime(user) do
    AuthService.get_last_successful_login_datetime(user)
  end

  @doc """
  Gets the last successful login event for a user.
  Returns nil if no successful login is found.
  """
  def get_last_successful_login_event(user) do
    AuthService.get_last_successful_login_event(user)
  end

  @doc """
  Gets recent authentication events for a user.
  """
  def get_user_auth_history(user, limit \\ 50) do
    AuthService.get_user_auth_history(user, limit)
  end

  @doc """
  Gets the last time a user was logged in (either login or logout event).
  This helps determine when the user was last active on the site.
  Returns nil if no login/logout events are found.
  """
  def get_last_login_session_datetime(user) do
    AuthService.get_last_login_session_datetime(user)
  end

  @doc """
  Gets the last login session event for a user (either login or logout).
  This helps determine when the user was last active on the site.
  Returns nil if no login/logout events are found.
  """
  def get_last_login_session_event(user) do
    AuthService.get_last_login_session_event(user)
  end

  @doc """
  Gets the time range when the user was last active on the site.
  Returns a map with :session_start and :session_end datetimes.
  This helps determine what content the user might have missed.
  """
  def get_last_session_timeframe(user) do
    AuthService.get_last_session_timeframe(user)
  end

  # Helper function to preload only active subscriptions
  defp preload_active_subscriptions(users) do
    user_ids = Enum.map(users, & &1.id)

    # Get active subscriptions for all users in one query
    active_subscriptions =
      from(s in Ysc.Subscriptions.Subscription,
        where: s.user_id in ^user_ids,
        where: s.stripe_status in ["active", "trialing", "past_due"],
        preload: [:subscription_items]
      )
      |> Repo.all()

    # Group subscriptions by user_id
    subscriptions_by_user =
      active_subscriptions
      |> Enum.group_by(& &1.user_id)

    # Preload primary_user for sub-accounts to avoid N+1 queries when checking inherited membership
    primary_user_ids =
      users
      |> Enum.filter(& &1.primary_user_id)
      |> Enum.map(& &1.primary_user_id)
      |> Enum.uniq()

    primary_users_by_id =
      if primary_user_ids != [] do
        # Get primary users with their active subscriptions
        primary_users =
          from(u in User, where: u.id in ^primary_user_ids) |> Repo.all()

        # Get subscriptions for primary users
        primary_user_subscriptions =
          from(s in Ysc.Subscriptions.Subscription,
            where: s.user_id in ^primary_user_ids,
            where: s.stripe_status in ["active", "trialing", "past_due"],
            preload: [:subscription_items]
          )
          |> Repo.all()

        # Group subscriptions by user_id
        primary_subscriptions_by_user =
          primary_user_subscriptions
          |> Enum.group_by(& &1.user_id)

        # Add subscriptions to primary users
        primary_users
        |> Enum.map(fn primary_user ->
          primary_user_subscriptions =
            Map.get(primary_subscriptions_by_user, primary_user.id, [])

          {primary_user.id,
           %{primary_user | subscriptions: primary_user_subscriptions}}
        end)
        |> Map.new()
      else
        %{}
      end

    # Add subscriptions and primary_user to each user
    Enum.map(users, fn user ->
      user_subscriptions = Map.get(subscriptions_by_user, user.id, [])

      primary_user =
        if user.primary_user_id,
          do: Map.get(primary_users_by_id, user.primary_user_id),
          else: nil

      user
      |> Map.put(:subscriptions, user_subscriptions)
      |> Map.put(:primary_user, primary_user)
    end)
  end

  # Helper function to extract membership_type filters from params
  defp extract_membership_filters(params) do
    case params do
      %{"filters" => filters} when is_map(filters) ->
        # Look for membership_type filter in the filters map
        membership_filter =
          Enum.find_value(filters, fn {_key, filter} ->
            case filter do
              %{"field" => "membership_type", "value" => value}
              when value != "" and value != [""] ->
                # Clean up the value - remove empty strings
                cleaned_value =
                  case value do
                    list when is_list(list) -> Enum.reject(list, &(&1 == ""))
                    other -> other
                  end

                if cleaned_value != [] and cleaned_value != "",
                  do: cleaned_value,
                  else: nil

              _ ->
                nil
            end
          end)

        if membership_filter do
          # Remove the membership_type filter from the filters map
          cleaned_filters =
            Enum.reject(filters, fn {_key, filter} ->
              case filter do
                %{"field" => "membership_type"} -> true
                _ -> false
              end
            end)
            |> Enum.with_index()
            |> Map.new(fn {filter, index} -> {to_string(index), filter} end)

          {membership_filter, Map.put(params, "filters", cleaned_filters)}
        else
          {nil, params}
        end

      _ ->
        {nil, params}
    end
  end

  # Helper function to apply membership filters to users
  defp apply_membership_filters(users, nil), do: users

  defp apply_membership_filters(users, membership_filters) do
    # Get membership plans for price ID lookup
    membership_plans = Application.get_env(:ysc, :membership_plans)

    price_to_type =
      Map.new(membership_plans, fn plan -> {plan.stripe_price_id, plan.id} end)

    Enum.filter(users, fn user ->
      user_membership_type =
        get_active_membership_type_for_filter(user, price_to_type)

      user_membership_type in membership_filters
    end)
  end

  # Helper function to get membership type for filtering
  defp get_active_membership_type_for_filter(user, price_to_type) do
    # Check for lifetime membership first (highest priority)
    if has_lifetime_membership?(user) do
      :lifetime
    else
      # Get all subscriptions for the user
      subscriptions =
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            # Fetch subscriptions if not loaded
            Ysc.Subscriptions.list_subscriptions(user)

          subscriptions when is_list(subscriptions) ->
            subscriptions

          _ ->
            []
        end

      # Filter for active subscriptions only
      active_subscriptions =
        Enum.filter(subscriptions, fn subscription ->
          Ysc.Subscriptions.valid?(subscription)
        end)

      case active_subscriptions do
        [] ->
          :none

        [single_subscription] ->
          get_membership_type_from_subscription_for_filter(
            single_subscription,
            price_to_type
          )

        multiple_subscriptions ->
          # If multiple active subscriptions, pick the most expensive one
          most_expensive =
            get_most_expensive_subscription_for_filter(multiple_subscriptions)

          get_membership_type_from_subscription_for_filter(
            most_expensive,
            price_to_type
          )
      end
    end
  end

  defp get_membership_type_from_subscription_for_filter(
         subscription,
         price_to_type
       ) do
    subscription_items =
      case subscription.subscription_items do
        %Ecto.Association.NotLoaded{} ->
          # Preload subscription items if not loaded
          subscription = Repo.preload(subscription, :subscription_items)
          subscription.subscription_items

        items when is_list(items) ->
          items

        _ ->
          []
      end

    case subscription_items do
      [item | _] ->
        Map.get(price_to_type, item.stripe_price_id, :none)

      _ ->
        :none
    end
  end

  defp get_most_expensive_subscription_for_filter(subscriptions) do
    membership_plans = Application.get_env(:ysc, :membership_plans)

    # Create a map of price_id to amount for quick lookup
    price_to_amount =
      Map.new(membership_plans, fn plan ->
        {plan.stripe_price_id, plan.amount}
      end)

    # Find the subscription with the highest amount
    Enum.max_by(subscriptions, fn subscription ->
      # Get the first subscription item (assuming one item per subscription)
      subscription_items =
        case subscription.subscription_items do
          %Ecto.Association.NotLoaded{} ->
            # Preload subscription items if not loaded
            subscription = Repo.preload(subscription, :subscription_items)
            subscription.subscription_items

          items when is_list(items) ->
            items

          _ ->
            []
        end

      case subscription_items do
        [item | _] ->
          Map.get(price_to_amount, item.stripe_price_id, 0)

        _ ->
          0
      end
    end)
  end

  # Helper function to extract membership_type sorting from params
  defp extract_membership_sort(params) do
    case params do
      %{"order_by" => order_by, "order_directions" => order_directions} ->
        # Check if membership_type is in the order_by list
        membership_sort_index =
          Enum.find_index(order_by, &(&1 == "membership_type"))

        if membership_sort_index do
          direction = Enum.at(order_directions, membership_sort_index, :asc)

          # Remove membership_type from order_by and order_directions
          new_order_by = List.delete_at(order_by, membership_sort_index)

          new_order_directions =
            List.delete_at(order_directions, membership_sort_index)

          new_params =
            params
            |> Map.put("order_by", new_order_by)
            |> Map.put("order_directions", new_order_directions)

          {{:membership_type, direction}, new_params}
        else
          {nil, params}
        end

      _ ->
        {nil, params}
    end
  end

  # Helper function to apply membership sorting to users
  defp apply_membership_sorting(users, nil), do: users

  defp apply_membership_sorting(users, {:membership_type, direction}) do
    # Get membership plans for sorting
    membership_plans = Application.get_env(:ysc, :membership_plans)

    price_to_type =
      Map.new(membership_plans, fn plan -> {plan.stripe_price_id, plan.id} end)

    # Define sort order for membership types
    membership_sort_order = %{
      :family => 1,
      :single => 2,
      :none => 3
    }

    Enum.sort_by(
      users,
      fn user ->
        membership_type =
          get_active_membership_type_for_filter(user, price_to_type)

        Map.get(membership_sort_order, membership_type, 4)
      end,
      direction
    )
  end

  @doc """
  Marks a user's email as verified by setting the email_verified_at timestamp.
  """
  def mark_email_verified(user) do
    user
    |> User.email_verification_changeset(%{
      email_verified_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Marks a user's phone as verified by setting the phone_verified_at timestamp.
  """
  def mark_phone_verified(user) do
    user
    |> User.phone_verification_changeset(%{
      phone_verified_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Marks a user's password as set by setting the password_set_at timestamp.
  """
  def mark_password_set(user) do
    user
    |> User.password_set_changeset(%{password_set_at: DateTime.utc_now()})
    |> Repo.update()
  end

  ## Family Account Functions

  @doc """
  Gets all users in a family group (primary user + all sub-accounts).
  """
  def get_family_group(user) do
    primary_user = if sub_account?(user), do: get_primary_user(user), else: user

    if primary_user do
      sub_accounts = get_sub_accounts(primary_user)
      [primary_user | sub_accounts]
    else
      [user]
    end
  end

  @doc """
  Gets all user IDs in a family group.
  Useful for querying bookings across the family.
  """
  def get_family_group_user_ids(user) do
    get_family_group(user)
    |> Enum.map(& &1.id)
  end

  @doc """
  Checks if a user is a primary user (not a sub-account).
  """
  def primary_user?(user) do
    is_nil(user.primary_user_id)
  end

  @doc """
  Checks if a user is a sub-account.
  """
  def sub_account?(user) do
    not is_nil(user.primary_user_id)
  end

  @doc """
  Gets the primary user for a sub-account.
  Returns nil if user is not a sub-account.
  """
  def get_primary_user(user) do
    if sub_account?(user) do
      case user.primary_user do
        %Ecto.Association.NotLoaded{} ->
          Repo.get(User, user.primary_user_id)

        primary_user when not is_nil(primary_user) ->
          primary_user

        _ ->
          Repo.get(User, user.primary_user_id)
      end
    else
      nil
    end
  end

  @doc """
  Gets all sub-accounts for a primary user.
  """
  def get_sub_accounts(primary_user) do
    case primary_user.sub_accounts do
      %Ecto.Association.NotLoaded{} ->
        from(u in User, where: u.primary_user_id == ^primary_user.id)
        |> Repo.all()

      sub_accounts when is_list(sub_accounts) ->
        sub_accounts

      _ ->
        []
    end
  end

  @doc """
  Checks if a user can send family invites.
  """
  def can_send_family_invite?(user) do
    Ysc.Accounts.FamilyInvites.can_send_family_invite?(user)
  end

  @doc """
  Removes a sub-account from a family group.
  This makes the sub-account independent (no longer associated with primary).
  """
  def remove_sub_account(sub_account, primary_user) do
    if sub_account.primary_user_id == primary_user.id do
      Ecto.Multi.new()
      |> Ecto.Multi.update(
        :sub_account,
        Ecto.Changeset.change(sub_account)
        |> Ecto.Changeset.put_change(:primary_user_id, nil)
      )
      |> Ecto.Multi.insert(
        :user_event,
        UserEvent.new_user_event_changeset(
          %UserEvent{},
          %{
            user_id: sub_account.id,
            updated_by_user_id: primary_user.id,
            type: :family_removed,
            from: "#{primary_user.id}",
            to: "none"
          }
        )
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{sub_account: updated_sub_account}} -> {:ok, updated_sub_account}
        {:error, _, changeset, _} -> {:error, changeset}
      end
    else
      {:error, :unauthorized}
    end
  end

  ## User Notes

  @doc """
  Creates a new note for a user.

  ## Examples

      iex> create_user_note(user, %{note: "User contacted support"}, admin_user)
      {:ok, %UserNote{}}

      iex> create_user_note(user, %{note: ""}, admin_user)
      {:error, %Ecto.Changeset{}}
  """
  def create_user_note(user, attrs, created_by_user) do
    attrs =
      attrs
      |> Map.put("user_id", user.id)
      |> Map.put("created_by_user_id", created_by_user.id)

    %UserNote{}
    |> UserNote.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all notes for a user, ordered by most recent first.

  Preloads the `created_by` association to show which admin created each note.

  ## Examples

      iex> list_user_notes(user_id)
      [%UserNote{...}, ...]
  """
  def list_user_notes(user_id) do
    from(n in UserNote,
      where: n.user_id == ^user_id,
      order_by: [desc: n.inserted_at],
      preload: [:created_by]
    )
    |> Repo.all()
  end

  # Helper function to check if we're in dev/sandbox mode
  defp dev_or_sandbox? do
    Ysc.Env.non_prod?()
  end
end
