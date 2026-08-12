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
    BoardPosition,
    Email,
    FamilyInvite,
    MembershipCache,
    User,
    UserProfileCache,
    UserToken,
    UserNotifier,
    AuthService,
    UserNote,
    UserPasskey
  }

  alias Ysc.Newsletter
  alias Ysc.Subscriptions.BoardVolunteerBilling
  alias Ysc.Subscriptions.{Subscription, SubscriptionItem}

  @blocked_session_states [:suspended, :rejected, :deleted]

  ## Database getters

  @doc """
  Gets a user by email.

  Normalizes the email before lookup to handle Gmail aliases
  (dots and plus-addressing).

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    normalized_email = Email.normalize(email)

    case Repo.get_by(User, email: normalized_email) do
      %User{} = user ->
        user

      nil ->
        find_user_by_canonical_email(normalized_email)
    end
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

  defp find_user_by_canonical_email(normalized_email) do
    if Email.gmail?(normalized_email) do
      [_local, domain] = String.split(normalized_email, "@", parts: 2)

      from(u in User, where: ilike(u.email, ^"%@#{domain}"))
      |> Repo.all()
      |> Enum.find(fn user ->
        Email.normalize(user.email) == normalized_email
      end)
    else
      nil
    end
  end

  @spec get_user_by_email_and_password(binary(), binary()) :: any()
  @doc """
  Gets a user by email and password.

  Normalizes the email before lookup to handle Gmail aliases
  (dots and plus-addressing).

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
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
    Ysc.Accounts.UserProfileCache.get_user!(id, preloads)
  end

  def get_user_from_db!(id, preloads \\ []) do
    Repo.get!(User, id) |> Repo.preload(preloads)
  end

  defp invalidate_user_profile_cache(%User{id: id}),
    do: UserProfileCache.invalidate_user(id)

  defp invalidate_user_profile_cache(id) when is_binary(id),
    do: UserProfileCache.invalidate_user(id)

  defp invalidate_user_profile_cache(_), do: :ok

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

  @doc """
  Returns whether the user has a password set in the database.

  Used to avoid overwriting an existing password when the in-memory user
  struct might be stale (e.g. hashed_password not loaded or from cache).
  Pass a user struct or user id.
  """
  def user_has_password_in_db?(%User{id: id}), do: user_has_password_in_db?(id)

  def user_has_password_in_db?(user_id) when not is_nil(user_id) do
    from(u in User,
      where: u.id == ^user_id,
      select: not is_nil(u.hashed_password)
    )
    |> Repo.one()
  end

  def get_user_from_stripe_id(stripe_id) do
    Repo.get_by(User, stripe_id: stripe_id)
  end

  ## Passkey functions

  @doc """
  Gets all passkeys for a user.

  When `:passkeys` is already preloaded on `user`, returns the in-memory list
  sorted like the database query (`last_used_at` descending) instead of
  issuing a second round-trip.
  """
  def get_user_passkeys(user) do
    if Ecto.assoc_loaded?(user.passkeys) do
      sort_passkeys_by_last_used_desc(user.passkeys)
    else
      from(p in UserPasskey,
        where: p.user_id == ^user.id,
        order_by: [desc: p.last_used_at]
      )
      |> Repo.all()
    end
  end

  defp sort_passkeys_by_last_used_desc(passkeys) do
    Enum.sort_by(
      passkeys,
      fn p ->
        ts =
          case p.last_used_at do
            %DateTime{} = dt -> DateTime.to_unix(dt, :microsecond)
            _ -> 0
          end

        {ts, p.id}
      end,
      :desc
    )
  end

  @doc """
  Gets a user passkey by external_id (credential ID).
  """
  def get_user_passkey_by_external_id(external_id) do
    Repo.get_by(UserPasskey, external_id: external_id)
  end

  @doc """
  Gets a user by email with passkeys preloaded.

  Normalizes the email before lookup to handle Gmail aliases
  (dots and plus-addressing).
  """
  def get_user_by_email_for_passkey(email) when is_binary(email) do
    case get_user_by_email(email) do
      nil -> nil
      user -> Repo.preload(user, :passkeys)
    end
  end

  @doc """
  Creates a new user passkey.
  """
  def create_user_passkey(user, attrs) do
    case %UserPasskey{}
         |> UserPasskey.create_changeset(Map.merge(attrs, %{user_id: user.id}))
         |> Repo.insert() do
      {:ok, _} = ok ->
        invalidate_user_profile_cache(user)
        ok

      error ->
        error
    end
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
    case Repo.delete(passkey) do
      {:ok, _} = ok ->
        invalidate_user_profile_cache(passkey.user_id)
        ok

      error ->
        error
    end
  end

  @doc """
  Checks if the passkey prompt should be shown to a user.

  Returns true if:
  - User has no passkeys
  - Either passkey_prompt_dismissed_at is nil OR it's been more than 30 days since dismissal
  """
  def should_show_passkey_prompt?(user) do
    # Always query the database: preloaded :passkeys from UserProfileCache can be
    # stale if the user registered a passkey during the same session.
    if user_has_passkeys?(user) do
      false
    else
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
    end
  end

  defp user_has_passkeys?(user) do
    from(p in UserPasskey, where: p.user_id == ^user.id, select: 1, limit: 1)
    |> Repo.exists?()
  end

  @doc """
  Dismisses the passkey prompt for a user by setting passkey_prompt_dismissed_at to current time.
  """
  def dismiss_passkey_prompt(user) do
    case user
         |> User.update_user_changeset(%{
           passkey_prompt_dismissed_at: DateTime.utc_now()
         })
         |> Repo.update() do
      {:ok, _} = ok ->
        invalidate_user_profile_cache(user)
        ok

      error ->
        error
    end
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
      limit: ^limit,
      preload: [:current_avatar]
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
    started_at = extract_registration_started(attrs)
    family_invite_id = extract_registration_family_invite_id(attrs)
    attrs = sanitize_registration_attrs(attrs)

    Repo.transaction(fn ->
      case %User{}
           |> User.registration_changeset(attrs, require_password: false)
           |> Repo.insert() do
        {:ok, user} ->
          # Preload registration_form within the same transaction
          # This ensures the association is available immediately after insert
          user = Repo.preload(user, :registration_form)
          user = stamp_signup_application_submission(user, started_at)

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

          user =
            link_family_invite_to_signup_application(user, family_invite_id)

          # Create billing address from signup application
          # This happens within the same transaction, so registration_form is guaranteed to be available
          case create_billing_address_from_signup(user) do
            {:ok, _address} ->
              :ok

            {:error, changeset} ->
              # Log the error but don't fail registration
              require Ysc.Logging

              Ysc.Logging.warning(
                "Failed to create billing address during registration",
                user_id: user.id,
                errors: inspect(changeset.errors)
              )
          end

          # Mark onboarding as complete immediately for new UI-registered users.
          # WP-migrated users are inserted directly via registration_changeset (not
          # through this function) and will have this field as nil, triggering the
          # post-migration onboarding wizard on their first login.
          {:ok, user} =
            user
            |> Ecto.Changeset.change(
              post_migration_onboarding_completed_at:
                DateTime.truncate(DateTime.utc_now(), :second)
            )
            |> Repo.update()

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
        if !is_test do
          Task.start(fn ->
            try do
              Ysc.Customers.create_stripe_customer(user)
            rescue
              e ->
                require Ysc.Logging

                Ysc.Logging.warning(
                  "Failed to create Stripe customer in background task",
                  user_id: user.id,
                  error: Exception.format(:error, e, __STACKTRACE__)
                )
            catch
              kind, reason ->
                require Ysc.Logging

                Ysc.Logging.warning(
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

  @registration_form_client_drop_keys ~w(
    started completed family_invite_id user_id
    reviewed_at review_outcome reviewed_by_user_id
  )a

  defp sanitize_registration_attrs(attrs) when is_map(attrs) do
    attrs
    |> sanitize_registration_form_attrs()
    |> sanitize_family_members_attrs()
  end

  defp sanitize_registration_form_attrs(attrs) do
    case registration_form_params(attrs) do
      nil ->
        attrs

      form ->
        put_registration_form_params(
          attrs,
          drop_registration_form_client_keys(form)
        )
    end
  end

  defp drop_registration_form_client_keys(form) when is_map(form) do
    string_keys = Enum.map(@registration_form_client_drop_keys, &to_string/1)
    Map.drop(form, @registration_form_client_drop_keys ++ string_keys)
  end

  defp sanitize_family_members_attrs(attrs) do
    cond do
      is_list(Map.get(attrs, "family_members")) ->
        Map.put(
          attrs,
          "family_members",
          sanitize_family_member_list(attrs["family_members"])
        )

      is_list(Map.get(attrs, :family_members)) ->
        Map.put(
          attrs,
          :family_members,
          sanitize_family_member_list(attrs[:family_members])
        )

      is_map(Map.get(attrs, "family_members")) ->
        Map.put(
          attrs,
          "family_members",
          sanitize_family_member_map(attrs["family_members"])
        )

      is_map(Map.get(attrs, :family_members)) ->
        Map.put(
          attrs,
          :family_members,
          sanitize_family_member_map(attrs[:family_members])
        )

      true ->
        attrs
    end
  end

  defp sanitize_family_member_list(members),
    do: Enum.map(members, &drop_family_member_client_keys/1)

  defp sanitize_family_member_map(members),
    do:
      Map.new(members, fn {key, member} ->
        {key, drop_family_member_client_keys(member)}
      end)

  defp drop_family_member_client_keys(member) when is_map(member) do
    Map.drop(member, ["id", "user_id", :id, :user_id])
  end

  defp drop_family_member_client_keys(other), do: other

  defp registration_form_params(attrs) do
    Map.get(attrs, "registration_form") || Map.get(attrs, :registration_form)
  end

  defp put_registration_form_params(attrs, form) do
    if Map.has_key?(attrs, "registration_form") do
      Map.put(attrs, "registration_form", form)
    else
      Map.put(attrs, :registration_form, form)
    end
  end

  defp extract_registration_started(attrs) do
    attrs
    |> registration_form_params()
    |> case do
      nil -> nil
      form -> Map.get(form, "started") || Map.get(form, :started)
    end
    |> parse_registration_timestamp()
    |> case do
      nil -> DateTime.utc_now() |> DateTime.truncate(:second)
      dt -> dt
    end
  end

  defp parse_registration_timestamp(nil), do: nil

  defp parse_registration_timestamp(%DateTime{} = dt),
    do: DateTime.truncate(dt, :second)

  defp parse_registration_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} ->
        DateTime.truncate(dt, :second)

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} ->
            naive
            |> DateTime.from_naive!("Etc/UTC")
            |> DateTime.truncate(:second)

          _ ->
            nil
        end
    end
  end

  defp parse_registration_timestamp(_), do: nil

  defp stamp_signup_application_submission(%User{} = user, started_at) do
    completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    case user.registration_form do
      %SignupApplication{} = application ->
        case application
             |> Ecto.Changeset.change(%{
               started: started_at,
               completed: completed_at
             })
             |> Repo.update() do
          {:ok, _} -> Repo.preload(user, :registration_form, force: true)
          {:error, _} -> user
        end

      _ ->
        user
    end
  end

  defp extract_registration_family_invite_id(attrs) do
    case registration_form_params(attrs) do
      nil ->
        nil

      form ->
        Map.get(form, "family_invite_id") || Map.get(form, :family_invite_id)
    end
  end

  # Links a family invite to the signup application only when the invite email matches
  # the registering user. Ignores forged `family_invite_id` values from client params.
  defp link_family_invite_to_signup_application(user, invite_id) do
    with invite_id when is_binary(invite_id) and invite_id != "" <- invite_id,
         %SignupApplication{} = application <- user.registration_form,
         %FamilyInvite{} = invite <- Repo.get(FamilyInvite, invite_id),
         true <-
           String.downcase(invite.email) == String.downcase(user.email) do
      case application
           |> Ecto.Changeset.change(family_invite_id: invite.id)
           |> Repo.update() do
        {:ok, _} ->
          Repo.preload(user, :registration_form, force: true)

        {:error, _} ->
          user
      end
    else
      _ -> user
    end
  end

  @doc false
  def create_billing_address_from_signup(user) do
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
            require Ysc.Logging

            Ysc.Logging.warning(
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
          require Ysc.Logging

          Ysc.Logging.warning(
            "Skipping billing address creation - registration_form not found",
            user_id: user.id
          )

          {:ok, nil}
        end

      # Association loaded but nil
      true ->
        require Ysc.Logging

        Ysc.Logging.warning(
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
    # Subscribe user to newsletter. Failures are logged but don't affect user registration.
    # If the email was already subscribed (e.g. public signup), the record is linked to the user.
    metadata = %{
      "user_id" => user.id,
      "signup_date" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "role" => to_string(user.role || "member"),
      "state" => to_string(user.state || "active")
    }

    case Newsletter.subscribe(user.email,
           user_id: user.id,
           first_name: user.first_name,
           last_name: user.last_name,
           source: "user_registration",
           metadata: metadata
         ) do
      {:ok, _subscriber} ->
        :ok

      {:error, :invalid_email} ->
        :ok

      {:error, %Ecto.Changeset{} = changeset} ->
        require Ysc.Logging

        Ysc.Logging.warning("Failed to subscribe user to newsletter",
          user_id: user.id,
          email: user.email,
          errors: inspect(changeset.errors)
        )

        :ok

      {:error, reason} ->
        require Ysc.Logging

        Ysc.Logging.warning("Failed to subscribe user to newsletter",
          user_id: user.id,
          email: user.email,
          reason: inspect(reason)
        )

        :ok
    end
  end

  @doc """
  Updates newsletter subscription when user changes email.
  Unsubscribes the old email. Subscribes the new email only if the old email
  was subscribed (per newsletter_subscribers table).
  """
  def update_newsletter_on_email_change(user, old_email, new_email) do
    require Ysc.Logging

    # Check if old email was subscribed before we unsubscribe (source of truth: newsletter_subscribers)
    was_subscribed =
      case Newsletter.get_subscriber_by_email(old_email) do
        nil -> false
        sub -> sub.subscribed
      end

    case Newsletter.unsubscribe(old_email) do
      {:ok, _} ->
        Ysc.Logging.debug("Unsubscribed old email from newsletter",
          user_id: user.id,
          old_email: old_email
        )

      {:error, :not_found} ->
        :ok

      {:error, _} ->
        Ysc.Logging.warning("Failed to unsubscribe old email from newsletter",
          user_id: user.id,
          old_email: old_email
        )
    end

    if was_subscribed do
      metadata = %{
        "user_id" => user.id,
        "email_changed_date" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "role" => to_string(user.role || "member"),
        "state" => to_string(user.state || "active")
      }

      case Newsletter.subscribe(new_email,
             user_id: user.id,
             first_name: user.first_name,
             last_name: user.last_name,
             source: "email_change",
             metadata: metadata
           ) do
        {:ok, _} ->
          Ysc.Logging.debug("Subscribed new email to newsletter",
            user_id: user.id,
            new_email: new_email
          )

          :ok

        {:error, _} ->
          Ysc.Logging.warning("Failed to subscribe new email to newsletter",
            user_id: user.id,
            new_email: new_email
          )

          :ok
      end
    else
      Ysc.Logging.debug(
        "Skipping newsletter subscription for new email (old email was not subscribed)",
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
      invalidate_user_profile_cache(updated_user)

      # Update Stripe customer with new phone information
      Task.start(fn ->
        Ysc.Customers.update_stripe_customer(updated_user)
      end)

      {:ok, updated_user}
    end
  end

  @doc """
  Generates a 6-digit verification code.

  Prefer `Ysc.Accounts.VerificationCodes` for issue/resend/verify flows.
  """
  def generate_email_verification_code do
    Ysc.Accounts.VerificationCodes.generate_code()
  end

  @doc """
  Stores an email verification code for a user with expiration.

  Prefer `Ysc.Accounts.VerificationCodes.store/4`.
  """
  def store_email_verification_code(user, code, expires_in_seconds \\ 600) do
    Ysc.Accounts.VerificationCodes.store(
      user,
      :email,
      code,
      expires_in_seconds
    )
  end

  @doc """
  Stores a phone verification code for a user.

  Prefer `Ysc.Accounts.VerificationCodes.store/4`.
  """
  def store_phone_verification_code(user, code, expires_in_seconds \\ 600) do
    Ysc.Accounts.VerificationCodes.store(
      user,
      :phone,
      code,
      expires_in_seconds
    )
  end

  @doc """
  Verifies an email verification code for a user (no attempt rate limit).

  Prefer `Ysc.Accounts.VerificationCodes.verify/3` in LiveViews.
  """
  def verify_email_verification_code(user, provided_code) do
    Ysc.Accounts.VerificationCodes.verify_unchecked(
      user,
      :email,
      provided_code
    )
  end

  @doc """
  Retrieves the current email verification code for a user if it exists and hasn't expired.
  """
  def get_email_verification_code(user) do
    Ysc.Accounts.VerificationCodes.get(user, :email)
  end

  @doc """
  Removes the email verification code for a user (useful for cleanup).
  """
  def remove_email_verification_code(user) do
    Ysc.Accounts.VerificationCodes.remove(user, :email)
  end

  @doc """
  Generates and stores an email verification code for a user.

  Prefer `Ysc.Accounts.VerificationCodes.issue/3` when the code should also be sent.
  """
  def generate_and_store_email_verification_code(
        user,
        expires_in_seconds \\ 600
      ) do
    Ysc.Accounts.VerificationCodes.generate_and_store(
      user,
      :email,
      expires_in_seconds
    )
  end

  @doc """
  Sends an email verification code to the user.

  Prefer `Ysc.Accounts.VerificationCodes.issue/3` or `resend/3`.
  """
  def send_email_verification_code(
        user,
        code,
        resend_key_suffix \\ nil,
        target_email \\ nil
      ) do
    Ysc.Accounts.VerificationCodes.deliver(user, :email, code,
      to: target_email,
      suffix: resend_key_suffix
    )
  end

  @doc """
  Generates and stores a phone verification code for a user.

  Prefer `Ysc.Accounts.VerificationCodes.issue/3` when the code should also be sent.
  """
  def generate_and_store_phone_verification_code(
        user,
        expires_in_seconds \\ 600
      ) do
    Ysc.Accounts.VerificationCodes.generate_and_store(
      user,
      :phone,
      expires_in_seconds
    )
  end

  @doc """
  Sends a phone verification code via SMS.

  Prefer `Ysc.Accounts.VerificationCodes.issue/3` or `resend/3`.
  """
  def send_phone_verification_code(
        user,
        code,
        resend_key_suffix \\ nil,
        to_phone \\ nil
      ) do
    Ysc.Accounts.VerificationCodes.deliver(user, :phone, code,
      to: to_phone,
      suffix: resend_key_suffix
    )
  end

  @doc """
  Verifies a phone verification code for a user (no attempt rate limit).

  Prefer `Ysc.Accounts.VerificationCodes.verify/3` in LiveViews.
  """
  def verify_phone_verification_code(user, provided_code) do
    Ysc.Accounts.VerificationCodes.verify_unchecked(
      user,
      :phone,
      provided_code
    )
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
      preload: [:current_avatar],
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
  Assigns a board position to a user and records it in history.

  Closes any current open board position record (sets `ended_on` to today),
  inserts a new `BoardPosition` with `started_on` today and `ended_on: nil`,
  and updates `user.board_position`.
  """
  def assign_board_position(%User{} = user, position)
      when not is_nil(position) do
    today = Date.utc_today()

    result =
      Repo.transaction(fn ->
        # Close any open board position for this user
        from(bp in BoardPosition,
          where: bp.user_id == ^user.id,
          where: is_nil(bp.ended_on)
        )
        |> Repo.update_all(set: [ended_on: today])

        # Insert new board position record
        %BoardPosition{}
        |> BoardPosition.changeset(%{
          user_id: user.id,
          position: position,
          started_on: today,
          ended_on: nil
        })
        |> Repo.insert!()

        # Update user's current board position
        user
        |> Ecto.Changeset.change(%{board_position: position})
        |> Repo.update!()
      end)

    enqueue_board_volunteer_stripe_sync(result)
    result
  end

  @doc """
  Removes the user's board position and closes the current record in history.

  Sets `ended_on` to today on the open `BoardPosition` (if any) and clears
  `user.board_position`.
  """
  def remove_board_position(%User{} = user) do
    today = Date.utc_today()

    result =
      Repo.transaction(fn ->
        from(bp in BoardPosition,
          where: bp.user_id == ^user.id,
          where: is_nil(bp.ended_on)
        )
        |> Repo.update_all(set: [ended_on: today])

        user
        |> Ecto.Changeset.change(%{board_position: nil, board_bio: nil})
        |> Repo.update!()
      end)

    enqueue_board_volunteer_stripe_sync(result)
    result
  end

  # Sync synchronously so a rapid remove+reassign cannot leave a stale
  # grace-period `resumes_at` from an earlier async Task finishing last.
  defp enqueue_board_volunteer_stripe_sync({:ok, %User{} = user}) do
    if BoardVolunteerBilling.household_on_board?(user) do
      BoardVolunteerBilling.sync_for_user(user)
    else
      BoardVolunteerBilling.sync_for_user(user, apply_off_board_grace?: true)
    end
  end

  defp enqueue_board_volunteer_stripe_sync(_), do: :ok

  @doc """
  Returns all board position records for a user, most recent first.
  Uses started_on then inserted_at so same-day entries have deterministic order.
  """
  def list_board_position_history(%User{} = user) do
    from(bp in BoardPosition,
      where: bp.user_id == ^user.id,
      order_by: [desc: bp.started_on, desc: bp.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets all users that have signed up and need their application reviewed.
  These are users with pending_approval state.
  """
  def get_pending_approval_users do
    list_pending_approval_users()
  end

  @doc """
  Returns the number of users awaiting application review.
  """
  def count_pending_approval_users do
    pending_approval_users_base_query()
    |> select([u], count(u.id))
    |> Repo.one()
  end

  @doc """
  Lists users awaiting application review, oldest first.

  Pass `limit:` to cap rows (e.g. admin dashboard preview cards).
  """
  def list_pending_approval_users(opts \\ []) do
    pending_approval_users_query()
    |> maybe_limit_pending_approval_users(Keyword.get(opts, :limit))
    |> Repo.all()
  end

  defp pending_approval_users_base_query do
    from u in User, where: u.state == :pending_approval
  end

  defp pending_approval_users_query do
    pending_approval_users_base_query()
    |> preload([:registration_form, :current_avatar])
    |> order_by([u], asc: u.inserted_at, asc: u.id)
  end

  defp maybe_limit_pending_approval_users(query, nil), do: query

  defp maybe_limit_pending_approval_users(query, limit)
       when is_integer(limit) and limit > 0 do
    from u in query, limit: ^limit
  end

  def list_paginated_users(params) do
    now = DateTime.utc_now()
    params = maybe_default_order(params, "application_date")
    {membership_filters, other_params} = extract_membership_filters(params)
    {order_by, order_directions, other_params} = extract_full_order(other_params)

    base_query =
      from(u in User, where: u.state != :deleted)
      |> build_membership_query_filter(membership_filters, now)
      |> apply_user_order_by(order_by, order_directions, now)

    case Flop.validate_and_run(base_query, other_params, for: User) do
      {:ok, {users, meta}} ->
        meta =
          restore_membership_filters(meta, membership_filters)
          |> restore_full_order(order_by, order_directions)

        {:ok,
         {preload_registration_forms(preload_active_subscriptions(users)), meta}}

      error ->
        error
    end
  end

  defp fuzzy_search_user(search_term, opts) do
    term = String.trim(search_term)
    rank? = Keyword.get(opts, :rank, true)
    words = String.split(term, ~r/\s+/, trim: true)

    case words do
      [w1, w2 | _] -> build_multi_word_search(term, w1, w2, rank?)
      _ -> build_single_word_search(term, rank?)
    end
  end

  defp build_single_word_search(term, rank?) do
    lower_term = String.downcase(term)
    prefix_like = "#{lower_term}%"
    contains_like = "%#{term}%"

    query =
      from(u in User,
        where:
          u.state != :deleted and
            (fragment("LOWER(?) = ?", u.email, ^lower_term) or
               fragment("LOWER(?) = ?", u.first_name, ^lower_term) or
               fragment("LOWER(?) = ?", u.last_name, ^lower_term) or
               fragment("LOWER(?) LIKE ?", u.first_name, ^prefix_like) or
               fragment("LOWER(?) LIKE ?", u.last_name, ^prefix_like) or
               fragment("LOWER(?) LIKE ?", u.email, ^prefix_like) or
               ilike(u.phone_number, ^contains_like) or
               fragment("SIMILARITY(?, ?) > 0.35", u.first_name, ^term) or
               fragment("SIMILARITY(?, ?) > 0.35", u.last_name, ^term) or
               fragment("SIMILARITY(?, ?) > 0.45", u.email, ^term))
      )

    if rank? do
      from(u in query,
        order_by: [
          desc:
            fragment(
              """
              CASE WHEN LOWER(?) = ? OR LOWER(?) = ? THEN 50 ELSE 0 END +
              CASE WHEN LOWER(?) = ? THEN 50 ELSE 0 END +
              CASE WHEN ? ILIKE ? THEN 40 ELSE 0 END +
              GREATEST(SIMILARITY(?, ?), SIMILARITY(?, ?), SIMILARITY(?, ?)) * 20
              """,
              u.first_name,
              ^lower_term,
              u.last_name,
              ^lower_term,
              u.email,
              ^lower_term,
              u.phone_number,
              ^contains_like,
              u.first_name,
              ^term,
              u.last_name,
              ^term,
              u.email,
              ^term
            )
        ]
      )
    else
      query
    end
  end

  defp build_multi_word_search(term, w1, w2, rank?) do
    lower_w1 = String.downcase(w1)
    lower_w2 = String.downcase(w2)
    lower_term = String.downcase(term)
    contains_like = "%#{term}%"
    prefix_w1 = "#{lower_w1}%"
    prefix_w2 = "#{lower_w2}%"

    query =
      from(u in User,
        where:
          u.state != :deleted and
            ((fragment("LOWER(?) = ?", u.first_name, ^lower_w1) and
                fragment("LOWER(?) = ?", u.last_name, ^lower_w2)) or
               (fragment("LOWER(?) = ?", u.first_name, ^lower_w2) and
                  fragment("LOWER(?) = ?", u.last_name, ^lower_w1)) or
               (fragment("LOWER(?) LIKE ?", u.first_name, ^prefix_w1) and
                  fragment("LOWER(?) LIKE ?", u.last_name, ^prefix_w2)) or
               (fragment("LOWER(?) LIKE ?", u.first_name, ^prefix_w2) and
                  fragment("LOWER(?) LIKE ?", u.last_name, ^prefix_w1)) or
               fragment("LOWER(?) = ?", u.email, ^lower_term) or
               ilike(u.phone_number, ^contains_like) or
               (fragment(
                  "GREATEST(SIMILARITY(?, ?), SIMILARITY(?, ?)) > 0.35",
                  u.first_name,
                  ^w1,
                  u.first_name,
                  ^w2
                ) and
                  fragment(
                    "GREATEST(SIMILARITY(?, ?), SIMILARITY(?, ?)) > 0.35",
                    u.last_name,
                    ^w1,
                    u.last_name,
                    ^w2
                  )))
      )

    if rank? do
      from(u in query,
        order_by: [
          desc:
            fragment(
              """
              CASE WHEN (LOWER(?) = ? AND LOWER(?) = ?) OR
                        (LOWER(?) = ? AND LOWER(?) = ?) THEN 100 ELSE 0 END +
              CASE WHEN LOWER(?) = ? THEN 50 ELSE 0 END +
              CASE WHEN ? ILIKE ? THEN 40 ELSE 0 END +
              (GREATEST(SIMILARITY(?, ?), SIMILARITY(?, ?)) +
               GREATEST(SIMILARITY(?, ?), SIMILARITY(?, ?))) * 10
              """,
              u.first_name,
              ^lower_w1,
              u.last_name,
              ^lower_w2,
              u.first_name,
              ^lower_w2,
              u.last_name,
              ^lower_w1,
              u.email,
              ^lower_term,
              u.phone_number,
              ^contains_like,
              u.first_name,
              ^w1,
              u.first_name,
              ^w2,
              u.last_name,
              ^w1,
              u.last_name,
              ^w2
            )
        ]
      )
    else
      query
    end
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
    now = DateTime.utc_now()
    {membership_filters, other_params} = extract_membership_filters(params)
    {order_by, order_directions, other_params} = extract_full_order(other_params)

    has_explicit_sort = order_by != []

    base_query =
      fuzzy_search_user(search_term, rank: !has_explicit_sort)
      |> build_membership_query_filter(membership_filters, now)
      |> apply_user_order_by(order_by, order_directions, now)

    case Flop.validate_and_run(base_query, other_params, for: User) do
      {:ok, {users, meta}} ->
        meta =
          restore_membership_filters(meta, membership_filters)
          |> restore_full_order(order_by, order_directions)

        {:ok,
         {preload_registration_forms(preload_active_subscriptions(users)), meta}}

      error ->
        error
    end
  end

  defp explicit_sort?(%{"order_by" => [_ | _]}), do: true
  defp explicit_sort?(_), do: false

  def update_user(user, params, %User{} = current_user) do
    with :ok <- Policy.authorize(:user_update, current_user, user) do
      previous_user = user
      user = maybe_update_board_position_history(user, params)

      case user |> User.update_user_changeset(params) |> Repo.update() do
        {:ok, updated_user} ->
          updated_user =
            maybe_stop_comms_on_deleted_transition(previous_user, updated_user)

          revoke_sessions_if_blocked(updated_user)
          Ysc.Accounts.UserProfileCache.invalidate_user(updated_user.id)

          Task.start(fn ->
            Ysc.Customers.update_stripe_customer(updated_user)
          end)

          {:ok, updated_user}

        error ->
          error
      end
    end
  end

  @doc """
  Updates user and their billing address information.
  """
  def update_user_with_address(user, params, %User{} = current_user) do
    with :ok <- Policy.authorize(:user_update, current_user, user) do
      previous_user = user
      user = maybe_update_board_position_history(user, params)

      result =
        Repo.transaction(fn ->
          case user
               |> User.update_user_with_address_changeset(params)
               |> Repo.update() do
            {:ok, updated_user} ->
              maybe_log_state_change_event(
                previous_user,
                updated_user,
                current_user
              )

              updated_user

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)

      case result do
        {:ok, updated_user} ->
          updated_user =
            maybe_stop_comms_on_deleted_transition(previous_user, updated_user)

          revoke_sessions_if_blocked(updated_user)
          Ysc.Accounts.UserProfileCache.invalidate_user(updated_user.id)

          Task.start(fn ->
            Ysc.Customers.update_stripe_customer(updated_user)
          end)

          {:ok, updated_user}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Like `update_user_with_address/3`, but also inserts a rejection-category user note
  in the same database transaction. If the note insert fails, the user update is rolled back.
  """
  def update_user_with_address_and_rejection_override_note(
        user,
        params,
        note_text,
        %User{} = current_user
      )
      when is_binary(note_text) do
    with :ok <- Policy.authorize(:user_update, current_user, user) do
      result =
        Repo.transaction(fn ->
          user = maybe_update_board_position_history(user, params)

          case user
               |> User.update_user_with_address_changeset(params)
               |> Repo.update() do
            {:ok, updated_user} ->
              note_attrs = %{
                "note" => note_text,
                "category" => "rejection",
                "user_id" => updated_user.id,
                "created_by_user_id" => current_user.id
              }

              case %UserNote{}
                   |> UserNote.changeset(note_attrs)
                   |> Repo.insert() do
                {:ok, _note} ->
                  maybe_log_state_change_event(user, updated_user, current_user)
                  updated_user

                {:error, changeset} ->
                  Repo.rollback(changeset)
              end

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)

      case result do
        {:ok, updated_user} ->
          updated_user =
            maybe_stop_comms_on_deleted_transition(user, updated_user)

          revoke_sessions_if_blocked(updated_user)
          Ysc.Accounts.UserProfileCache.invalidate_user(updated_user.id)

          Task.start(fn ->
            Ysc.Customers.update_stripe_customer(updated_user)
          end)

          {:ok, updated_user}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, changeset}

        {:error, other} ->
          {:error, other}
      end
    end
  end

  defp revoke_sessions_if_blocked(%User{state: state} = user)
       when state in @blocked_session_states do
    revoke_all_user_sessions(user)
  end

  defp revoke_sessions_if_blocked(_user), do: :ok

  # Audit-logs direct account-status edits (e.g. the admin Profile tab's
  # "Account Status" dropdown) the same way record_application_outcome/4
  # already does for the Approve/Deny buttons, so membership reporting can
  # rely on a single UserEvent trail regardless of which admin flow changed
  # a user's state.
  defp maybe_log_state_change_event(
         %User{state: state},
         %User{state: state},
         _current_user
       ),
       do: :ok

  defp maybe_log_state_change_event(
         %User{} = previous_user,
         %User{} = updated_user,
         %User{} = current_user
       ) do
    %UserEvent{}
    |> UserEvent.new_user_event_changeset(%{
      user_id: updated_user.id,
      updated_by_user_id: current_user.id,
      type: :state_update,
      from: "#{previous_user.state}",
      to: "#{updated_user.state}"
    })
    |> Repo.insert!()

    :ok
  end

  # When an account is soft-deleted, stop marketing/ops outbound channels:
  # unsubscribe newsletter and disable event/SMS preference flags. Session
  # revocation is handled separately by revoke_sessions_if_blocked/1.
  defp maybe_stop_comms_on_deleted_transition(
         %User{state: previous_state},
         %User{state: :deleted} = user
       )
       when previous_state != :deleted do
    stop_outbound_comms_for_deleted_user(user)
  end

  defp maybe_stop_comms_on_deleted_transition(_previous, user), do: user

  defp stop_outbound_comms_for_deleted_user(%User{} = user) do
    require Ysc.Logging

    case Newsletter.unsubscribe(user.email) do
      {:ok, _} ->
        :ok

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        Ysc.Logging.warning(
          "Failed to unsubscribe deleted user from newsletter",
          user_id: user.id,
          extra: %{reason: inspect(reason)}
        )
    end

    case user
         |> User.notification_preferences_changeset(%{
           event_notifications: false,
           event_notifications_sms: false,
           account_notifications_sms: false,
           account_notifications: true
         })
         |> Repo.update() do
      {:ok, updated_user} ->
        invalidate_user_profile_cache(updated_user)
        updated_user

      {:error, changeset} ->
        Ysc.Logging.warning(
          "Failed to disable notification preferences for deleted user",
          user_id: user.id,
          extra: %{errors: inspect(changeset.errors)}
        )

        user
    end
  end

  defp maybe_update_board_position_history(user, params) do
    new_val =
      Map.get(params, "board_position") || Map.get(params, :board_position)

    current = user.board_position
    new_normalized = normalize_board_position_param(new_val)
    current_normalized = if current, do: to_string(current), else: nil

    if new_normalized != current_normalized do
      if new_normalized in [nil, ""] do
        {:ok, updated} = remove_board_position(user)
        updated
      else
        position_atom =
          if is_binary(new_normalized) do
            String.to_existing_atom(new_normalized)
          else
            new_normalized
          end

        {:ok, updated} = assign_board_position(user, position_atom)
        updated
      end
    else
      user
    end
  end

  defp normalize_board_position_param(nil), do: nil
  defp normalize_board_position_param(""), do: nil
  defp normalize_board_position_param(v) when is_binary(v), do: v
  defp normalize_board_position_param(v) when is_atom(v), do: to_string(v)

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
      Ysc.Accounts.UserProfileCache.invalidate_user(updated_user.id)

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
    case user
         |> User.notification_preferences_changeset(attrs)
         |> Repo.update() do
      {:ok, _} = ok ->
        invalidate_user_profile_cache(user)
        ok

      error ->
        error
    end
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
      Ysc.Accounts.UserProfileCache.invalidate_user(user.id)
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
      invalidate_user_profile_cache(reloaded_user)

      # Update Stripe customer with new email
      Task.start(fn ->
        Ysc.Customers.update_stripe_customer(reloaded_user)
      end)

      {:ok, reloaded_user, email}
    else
      _ -> :error
    end
  end

  @dialyzer {:nowarn_function, user_email_multi: 3}
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
    case Ysc.Payments.get_user_payment_method(user, payment_method_id) do
      nil ->
        {:error, :payment_method_not_owned_by_user}

      payment_method ->
        case Ysc.Payments.set_default_payment_method(user, payment_method) do
          {:ok, updated_user} = result ->
            Ysc.Payments.push_default_payment_method_to_stripe(
              updated_user,
              payment_method
            )

            result

          error ->
            error
        end
    end
  end

  @doc """
  Sets the initial password for a user during account setup.

  This is used when a user doesn't have a password yet and is setting one for the first time.
  Unlike update_user_password, this doesn't validate a current password.
  """
  @dialyzer {:nowarn_function, set_user_initial_password: 2}
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

  @dialyzer {:nowarn_function, update_user_password: 3}
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
  Generates a short-lived, one-time token for completing a passkey login redirect.

  Returns the raw (URL-safe Base64) token. Only the hash is stored in the DB.
  """
  def generate_passkey_login_token(user) do
    generate_one_time_login_token(user, &UserToken.build_passkey_login_token/1)
  end

  @doc """
  Generates a short-lived, one-time token for completing an auto-login redirect.

  Returns the raw (URL-safe Base64) token. Only the hash is stored in the DB.
  """
  def generate_auto_login_token(user) do
    generate_one_time_login_token(user, &UserToken.build_auto_login_token/1)
  end

  @doc """
  Verifies a passkey login token and returns the associated user if valid.

  The read and delete are executed inside a single DB transaction with a
  `FOR UPDATE` row-level lock. This prevents two concurrent requests from
  both reading the same token row before either has deleted it (replay
  window), ensuring strict one-time-use semantics even under load.
  """
  def verify_and_consume_passkey_login_token(token) do
    verify_and_consume_one_time_login_token(
      token,
      &UserToken.verify_passkey_login_token_query/1
    )
  end

  @doc """
  Verifies an auto-login token and returns the associated user if valid.

  Uses the same cluster-safe one-time consumption semantics as passkey login.
  """
  def verify_and_consume_auto_login_token(token) do
    verify_and_consume_one_time_login_token(
      token,
      &UserToken.verify_auto_login_token_query/1
    )
  end

  defp generate_one_time_login_token(user, builder) do
    {token, user_token} = builder.(user)
    Repo.insert!(user_token)
    token
  end

  defp verify_and_consume_one_time_login_token(token, verify_query) do
    case verify_query.(token) do
      {:ok, base_query} ->
        result =
          Repo.transaction(fn ->
            # Lock the matching row so concurrent callers must queue behind
            # this transaction rather than racing to read-then-delete.
            locked_query = from(q in base_query, lock: "FOR UPDATE")

            case Repo.one(locked_query) do
              {user, token_record} ->
                case Repo.delete(token_record) do
                  {:ok, _deleted} ->
                    user

                  {:error, _changeset} ->
                    Repo.rollback(:invalid_or_expired)
                end

              nil ->
                Repo.rollback(:invalid_or_expired)
            end
          end)

        case result do
          {:ok, user} -> {:ok, user}
          {:error, :invalid_or_expired} -> {:error, :invalid_or_expired}
        end

      :error ->
        {:error, :invalid_or_expired}
    end
  end

  @doc """
  Returns whether the user may keep an authenticated session.

  Matches login eligibility: only `:pending_approval` and `:active` users.
  """
  def login_allowed_state?(%User{state: state}),
    do: state in [:pending_approval, :active]

  def login_allowed_state?(_), do: false

  @doc """
  Returns whether outbound email/SMS should be delivered for this user.

  Soft-deleted accounts (`:deleted`) do not receive outbound comms.
  When `state` is absent (bare preference maps in tests/callers), returns
  `true` so preference-only checks keep working.
  """
  def receives_outbound_comms?(%User{state: :deleted}), do: false

  def receives_outbound_comms?(%{state: :deleted}), do: false

  def receives_outbound_comms?(_), do: true

  @doc """
  Deletes all session tokens for the given user.

  Used when an account is suspended, rejected, or deleted so existing cookies
  stop working immediately instead of remaining valid for up to 60 days.
  """
  def revoke_all_user_sessions(%User{} = user) do
    Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["session"]))
    :ok
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    user = Repo.one(query)

    if user && login_allowed_state?(user) do
      if user_subscriptions_fully_loaded?(user) do
        Repo.preload(user, :current_avatar)
      else
        load_user_for_session_with_membership_cache(user)
      end
    else
      nil
    end
  end

  defp load_user_for_session_with_membership_cache(user) do
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
        # Cache hit - skip subscription preload but still load avatar
        Repo.preload(user, :current_avatar)

      {:error, _reason} ->
        # Cache error - fallback to preloading for safety
        preload_active_subscriptions_for_auth(user)
    end
  end

  defp user_subscriptions_fully_loaded?(user) do
    Ecto.assoc_loaded?(user.subscriptions) and
      Enum.all?(user.subscriptions, fn sub ->
        Ecto.assoc_loaded?(sub.subscription_items)
      end)
  end

  @doc """
  Ensures a user has active subscriptions and subscription_items loaded for booking flows.
  Reuses existing preloads when present to avoid duplicate queries.
  """
  def preload_user_subscriptions_for_booking(user) do
    if user_subscriptions_fully_loaded?(user) do
      user
    else
      preload_active_subscriptions_for_auth(user)
    end
  end

  # Optimized preload that only fetches active subscriptions with subscription_items
  # This reduces queries from 2+ (user + all subscriptions) to 1 (user + active subscriptions)
  defp preload_active_subscriptions_for_auth(user) do
    if user_subscriptions_fully_loaded?(user) do
      Repo.preload(user, :current_avatar)
    else
      do_preload_active_subscriptions_for_auth(user)
    end
  end

  defp do_preload_active_subscriptions_for_auth(user) do
    active_subscriptions =
      from(s in Ysc.Subscriptions.Subscription,
        where: s.user_id == ^user.id,
        where: s.stripe_status in ["active", "trialing"],
        preload: [:subscription_items]
      )
      |> Repo.all()

    user
    |> Map.put(:subscriptions, active_subscriptions)
    |> Repo.preload(:current_avatar)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  @doc """
  Revokes a specific session for the user by encoded session ID (Base64).
  Used when the user signs out a session from the Security settings page.
  Returns :ok if the session was revoked, :error if invalid or not found.
  """
  def revoke_user_session_by_id(user, encoded_session_id)
      when is_binary(encoded_session_id) do
    case Base.decode64(encoded_session_id) do
      {:ok, token} ->
        query =
          from t in UserToken,
            where:
              t.user_id == ^user.id and t.context == "session" and
                t.token == ^token

        case Repo.delete_all(query) do
          {1, _} -> :ok
          _ -> :error
        end

      :error ->
        :error
    end
  end

  def deliver_application_submitted_notification(%User{} = user) do
    YscWeb.Emails.Notifier.schedule_email(
      user.email,
      "#{user.id}",
      "Your Young Scandinavians Club application is in! 🎉",
      "application_submitted",
      %{first_name: Ysc.title_case(user.first_name)},
      """
      ==============================

      Hi #{Ysc.title_case(user.first_name)},

      Your application has been submitted! 🎉

      We'll review your application and get back to you soon.

      In the meantime, check out our upcoming events and latest news on our website.

      ==============================
      """,
      user.id
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
  @dialyzer {:nowarn_function, reset_user_password: 2}
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.run(:mark_password_set, fn _repo, %{user: updated_user} ->
      updated_user
      |> User.password_set_changeset(%{password_set_at: DateTime.utc_now()})
      |> Repo.update()
    end)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, :all)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{mark_password_set: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :mark_password_set, changeset, _} -> {:error, changeset}
    end
  end

  def get_signup_application_submission_date(user_id) do
    from(s in SignupApplication,
      select: %{submit_date: s.completed, timezone: s.browser_timezone},
      where: s.user_id == ^user_id
    )
    |> Repo.one()
  end

  @dialyzer {:nowarn_function, record_application_outcome: 4}
  def record_application_outcome(:approved, user, application, current_user) do
    with :ok <-
           Policy.authorize(:signup_application_update, current_user, %{
             user_id: user.id
           }) do
      with :ok <-
             Policy.authorize(:user_update, current_user, %{user_id: user.id}) do
        # When application is linked to a family invite, load invite for linking
        {invite, user_approval_attrs} =
          if application.family_invite_id do
            invite = Repo.get!(FamilyInvite, application.family_invite_id)
            relationship = invite.relationship || "child"

            {invite,
             %{
               state: :active,
               date_of_birth: application.birth_date,
               primary_user_id: invite.primary_user_id,
               family_relationship: relationship
             }}
          else
            {nil,
             %{
               state: :active,
               date_of_birth: application.birth_date
             }}
          end

        base_multi =
          Ecto.Multi.new()
          |> Ecto.Multi.run(:family_invite_guard, fn repo, _changes ->
            if invite do
              case Ysc.Accounts.FamilyInvites.validate_invite_acceptance(
                     repo,
                     invite
                   ) do
                :ok -> {:ok, :ok}
                {:error, reason} -> {:error, reason}
              end
            else
              {:ok, :ok}
            end
          end)
          |> Ecto.Multi.update(
            :user,
            User.approve_user_changeset(user, user_approval_attrs)
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

        # When family invite, mark invite as accepted
        multi_with_invite =
          if invite do
            base_multi
            |> Ecto.Multi.update(
              :invite,
              FamilyInvite.accept_changeset(invite)
            )
          else
            base_multi
          end

        multi_with_invite
        |> Repo.transaction()
        |> case do
          {:ok, _} ->
            if invite do
              Ysc.Accounts.FamilyInvites.notify_invite_accepted(invite, user)
            end

            {:ok, application}

          {:error, _failed_operation, failed_value, _changes} ->
            {:error, failed_value}
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
          {:ok, %{user: updated_user}} ->
            revoke_sessions_if_blocked(updated_user)
            :ok

          {:ok, _} ->
            revoke_sessions_if_blocked(user)
            :ok

          {:error, _, changeset, _} ->
            {:error, changeset}
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
  Returns the last successful login and last login/logout activity timestamps
  for a user in a single database round trip.
  """
  def get_user_login_activity_datetimes(user) do
    AuthService.get_user_login_activity_datetimes(user)
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
    users = Repo.preload(users, :current_avatar)
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

  defp restore_membership_filters(meta, nil), do: meta

  defp restore_membership_filters(meta, membership_values) do
    membership_flop_filter = %Flop.Filter{
      field: :membership_type,
      op: :in,
      value: Enum.map(membership_values, &to_string/1)
    }

    updated_flop = %{
      meta.flop
      | filters: meta.flop.filters ++ [membership_flop_filter]
    }

    %{meta | flop: updated_flop}
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
                # Clean up the value - remove empty strings and atomize
                valid_types = ~w(single family lifetime none)

                cleaned_value =
                  case value do
                    list when is_list(list) ->
                      list
                      |> Enum.reject(&(&1 == ""))
                      |> Enum.filter(&(&1 in valid_types))
                      |> Enum.map(&String.to_existing_atom/1)

                    other when is_binary(other) ->
                      if other in valid_types,
                        do: [String.to_existing_atom(other)],
                        else: []

                    _ ->
                      []
                  end

                if cleaned_value != [], do: cleaned_value, else: nil

              _ ->
                nil
            end
          end)

        if membership_filter do
          # Remove the membership_type filter from the filters map
          cleaned_filters =
            filters
            |> Enum.reject(fn {_key, filter} ->
              match?(%{"field" => "membership_type"}, filter)
            end)
            |> Enum.with_index()
            |> Map.new(fn {{_key, filter_map}, index} ->
              {to_string(index), filter_map}
            end)

          {membership_filter, Map.put(params, "filters", cleaned_filters)}
        else
          {nil, params}
        end

      _ ->
        {nil, params}
    end
  end

  # Applies membership type filter at the DB query level so Flop pagination is accurate.
  defp build_membership_query_filter(query, nil, _now), do: query
  defp build_membership_query_filter(query, [], _now), do: query

  defp build_membership_query_filter(query, membership_filters, now) do
    membership_plans = Application.get_env(:ysc, :membership_plans)

    active_sub_user_ids =
      from s in Ysc.Subscriptions.Subscription,
        where: s.stripe_status in ["active", "trialing"],
        where: is_nil(s.current_period_end) or s.current_period_end > ^now,
        where: is_nil(s.ends_at) or s.ends_at > ^now,
        select: s.user_id

    # Build per-plan subqueries upfront so higher-tier plans can be excluded
    # from lower-tier filters (e.g. a user with family should not appear in
    # the single filter, even if they have a stale single subscription item).
    plan_user_id_subqueries =
      Map.new([:single, :family], fn plan_type ->
        price_id =
          Enum.find_value(membership_plans, fn p ->
            if p.id == plan_type, do: p.stripe_price_id
          end)

        subq =
          if price_id do
            from s in Ysc.Subscriptions.Subscription,
              join: si in assoc(s, :subscription_items),
              where: s.stripe_status in ["active", "trialing"],
              where:
                is_nil(s.current_period_end) or s.current_period_end > ^now,
              where: is_nil(s.ends_at) or s.ends_at > ^now,
              where: si.stripe_price_id == ^price_id,
              select: s.user_id
          end

        {plan_type, subq}
      end)

    condition =
      Enum.reduce(membership_filters, nil, fn type, acc ->
        type_condition =
          case type do
            :lifetime ->
              dynamic([u], not is_nil(u.lifetime_membership_awarded_at))

            :none ->
              dynamic(
                [u],
                is_nil(u.lifetime_membership_awarded_at) and
                  u.id not in subquery(active_sub_user_ids)
              )

            plan_type when plan_type in [:single, :family] ->
              case Map.get(plan_user_id_subqueries, plan_type) do
                nil ->
                  nil

                price_sub_query ->
                  # Reflect the user's effective membership (highest-tier wins).
                  # Exclude users with lifetime and users whose best plan is
                  # higher-tier (family beats single).
                  base =
                    dynamic(
                      [u],
                      u.id in subquery(price_sub_query) and
                        is_nil(u.lifetime_membership_awarded_at)
                    )

                  case {plan_type, Map.get(plan_user_id_subqueries, :family)} do
                    {:single, family_subq} when not is_nil(family_subq) ->
                      dynamic([u], ^base and u.id not in subquery(family_subq))

                    _ ->
                      base
                  end
              end

            _ ->
              nil
          end

        case {acc, type_condition} do
          {nil, nil} -> nil
          {nil, cond} -> cond
          {acc, nil} -> acc
          {acc, cond} -> dynamic([u], ^acc or ^cond)
        end
      end)

    if condition, do: where(query, ^condition), else: query
  end

  # Helper function to get membership type for filtering

  # `first_name`/`application_date`/`state`/`membership_type`/etc. can appear
  # in any order in `order_by`, and some of them (membership_type,
  # application_date) aren't real columns Flop can sort by directly, so they
  # can't just be handed to Flop. Pulling the "special" fields out of the
  # list and applying their raw-SQL sorts before/after Flop's own order_by
  # (as this module used to do) breaks multi-column sorts, because Ecto's
  # order_by is additive across query composition: whichever clause is added
  # to the query first wins precedence, regardless of the field's original
  # position in `order_by`. So instead we take over ordering entirely here,
  # applying every field - real or computed - as one query composition in
  # the exact sequence the caller asked for, and tell Flop not to order at
  # all (`order_by: []`) so it doesn't also append its own clause.
  defp extract_full_order(params) do
    case params do
      %{"order_by" => order_by, "order_directions" => order_directions}
      when is_list(order_by) and is_list(order_directions) ->
        new_params =
          params
          |> Map.put("order_by", [])
          |> Map.put("order_directions", [])

        {order_by, order_directions, new_params}

      _ ->
        {[], [], params}
    end
  end

  @user_order_known_fields ~w(email first_name last_name state role membership_type application_date)
  @user_order_native_fields ~w(email first_name last_name state role)

  defp apply_user_order_by(query, order_by, order_directions, now) do
    order_by
    |> Enum.zip(order_directions || [])
    |> Enum.reduce(query, fn {field, direction}, acc ->
      direction = if direction in ["desc", :desc], do: :desc, else: :asc
      apply_user_order_term(acc, field, direction, now)
    end)
  end

  defp apply_user_order_term(query, "membership_type", direction, now),
    do: apply_membership_order_by(query, {:membership_type, direction, 0}, now)

  defp apply_user_order_term(query, "application_date", direction, now) do
    apply_application_date_order_by(
      query,
      {:application_date, direction, 0},
      now
    )
  end

  defp apply_user_order_term(query, field, direction, _now)
       when field in @user_order_native_fields do
    atom = String.to_existing_atom(field)
    from(u in query, order_by: [{^direction, field(u, ^atom)}])
  end

  defp apply_user_order_term(query, _field, _direction, _now), do: query

  # Reconstructs the full requested sort in `meta.flop` (used to drive the
  # column sort arrows in the UI) since Flop itself was never given an
  # order_by to work with - see `extract_full_order/1`.
  defp restore_full_order(meta, [], _order_directions), do: meta

  defp restore_full_order(%Flop.Meta{} = meta, order_by, order_directions) do
    {fields, directions} =
      order_by
      |> Enum.zip(order_directions)
      |> Enum.filter(fn {field, _} -> field in @user_order_known_fields end)
      |> Enum.unzip()

    updated_flop = %{
      meta.flop
      | order_by: Enum.map(fields, &String.to_existing_atom/1),
        order_directions:
          Enum.map(directions, fn
            "desc" -> :desc
            _ -> :asc
          end)
    }

    %{meta | flop: updated_flop}
  end

  defp apply_membership_order_by(
         query,
         {:membership_type, direction, _index},
         now
       ) do
    membership_plans = Application.get_env(:ysc, :membership_plans)

    single_price =
      Enum.find_value(membership_plans, fn p ->
        if p.id == :single, do: p.stripe_price_id
      end)

    family_price =
      Enum.find_value(membership_plans, fn p ->
        if p.id == :family, do: p.stripe_price_id
      end)

    case direction do
      :asc ->
        from u in query,
          order_by:
            fragment(
              """
              CASE
                WHEN ? IS NOT NULL THEN 1
                WHEN EXISTS (
                  SELECT 1 FROM subscriptions s
                  JOIN subscription_items si ON si.subscription_id = s.id
                  WHERE s.user_id = ?
                    AND s.stripe_status IN ('active', 'trialing')
                    AND (s.current_period_end IS NULL OR s.current_period_end > ?)
                    AND (s.ends_at IS NULL OR s.ends_at > ?)
                    AND si.stripe_price_id = ?
                ) THEN 2
                WHEN EXISTS (
                  SELECT 1 FROM subscriptions s
                  JOIN subscription_items si ON si.subscription_id = s.id
                  WHERE s.user_id = ?
                    AND s.stripe_status IN ('active', 'trialing')
                    AND (s.current_period_end IS NULL OR s.current_period_end > ?)
                    AND (s.ends_at IS NULL OR s.ends_at > ?)
                    AND si.stripe_price_id = ?
                ) THEN 3
                ELSE 4
              END ASC
              """,
              u.lifetime_membership_awarded_at,
              u.id,
              ^now,
              ^now,
              ^family_price,
              u.id,
              ^now,
              ^now,
              ^single_price
            )

      :desc ->
        from u in query,
          order_by:
            fragment(
              """
              CASE
                WHEN ? IS NOT NULL THEN 1
                WHEN EXISTS (
                  SELECT 1 FROM subscriptions s
                  JOIN subscription_items si ON si.subscription_id = s.id
                  WHERE s.user_id = ?
                    AND s.stripe_status IN ('active', 'trialing')
                    AND (s.current_period_end IS NULL OR s.current_period_end > ?)
                    AND (s.ends_at IS NULL OR s.ends_at > ?)
                    AND si.stripe_price_id = ?
                ) THEN 2
                WHEN EXISTS (
                  SELECT 1 FROM subscriptions s
                  JOIN subscription_items si ON si.subscription_id = s.id
                  WHERE s.user_id = ?
                    AND s.stripe_status IN ('active', 'trialing')
                    AND (s.current_period_end IS NULL OR s.current_period_end > ?)
                    AND (s.ends_at IS NULL OR s.ends_at > ?)
                    AND si.stripe_price_id = ?
                ) THEN 3
                ELSE 4
              END DESC
              """,
              u.lifetime_membership_awarded_at,
              u.id,
              ^now,
              ^now,
              ^family_price,
              u.id,
              ^now,
              ^now,
              ^single_price
            )
    end
  end

  # If the caller didn't ask for a specific sort, default to the given virtual
  # field (desc) instead of the schema's own `default_order`. Runs before the
  # membership/application-date extractors so it flows through their normal
  # extract/apply/restore pipeline rather than needing a separate code path.
  defp maybe_default_order(%{"order_by" => _} = params, _field), do: params
  defp maybe_default_order(%{order_by: _} = params, _field), do: params

  defp maybe_default_order(params, field) when is_map(params) do
    # Normalize to string keys before injecting: the extract_*_sort/1
    # functions only pattern-match on string "order_by", and Ecto.Changeset.cast
    # (via Flop) rejects a map with mixed atom/string keys, so a params map
    # using atom keys (as in tests/iex) must be fully stringified first.
    params
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put("order_by", [field])
    |> Map.put("order_directions", ["desc"])
  end

  defp maybe_default_order(params, _field), do: params

  # Helper function to extract application_date sorting from params.
  # Mirrors extract_membership_sort/1 - application_date is a computed,
  # cross-table field (signup_applications), not a real column on User, so it
  # has to be pulled out before Flop sees it and applied as a raw SQL sort.
  defp extract_application_date_sort(params) do
    case params do
      %{"order_by" => order_by, "order_directions" => order_directions}
      when is_list(order_by) and is_list(order_directions) ->
        sort_index = Enum.find_index(order_by, &(&1 == "application_date"))

        if sort_index do
          direction =
            order_directions
            |> Enum.at(sort_index, "asc")
            |> then(fn
              "desc" -> :desc
              _ -> :asc
            end)

          new_order_by = List.delete_at(order_by, sort_index)

          new_order_directions =
            List.delete_at(order_directions, sort_index)

          new_params =
            params
            |> Map.put("order_by", new_order_by)
            |> Map.put("order_directions", new_order_directions)

          {{:application_date, direction, sort_index}, new_params}
        else
          {nil, params}
        end

      _ ->
        {nil, params}
    end
  end

  defp apply_application_date_order_by(query, nil, _now), do: query

  defp apply_application_date_order_by(
         query,
         {:application_date, direction, _index},
         _now
       ) do
    joined =
      from u in query,
        left_join: sa in SignupApplication,
        on: sa.user_id == u.id

    case direction do
      :asc ->
        from [u, sa] in joined,
          order_by: [
            asc_nulls_last:
              fragment(
                "COALESCE(?, ?, ?)",
                sa.completed,
                sa.reviewed_at,
                u.inserted_at
              )
          ]

      :desc ->
        from [u, sa] in joined,
          order_by: [
            desc_nulls_last:
              fragment(
                "COALESCE(?, ?, ?)",
                sa.completed,
                sa.reviewed_at,
                u.inserted_at
              )
          ]
    end
  end

  defp restore_application_date_sort(meta, nil), do: meta

  defp restore_application_date_sort(
         %Flop.Meta{} = meta,
         {:application_date, direction, index}
       ) do
    current_order_by = meta.flop.order_by || []
    current_directions = meta.flop.order_directions || []

    safe_index = min(index, length(current_order_by))

    updated_flop = %{
      meta.flop
      | order_by:
          List.insert_at(current_order_by, safe_index, :application_date),
        order_directions:
          List.insert_at(current_directions, safe_index, direction)
    }

    %{meta | flop: updated_flop}
  end

  defp preload_registration_forms(users),
    do: Repo.preload(users, :registration_form)

  @doc """
  Marks a user's email as verified by setting the email_verified_at timestamp.
  """
  def mark_email_verified(user) do
    case user
         |> User.email_verification_changeset(%{
           email_verified_at: DateTime.utc_now()
         })
         |> Repo.update() do
      {:ok, _} = ok ->
        invalidate_user_profile_cache(user)
        ok

      error ->
        error
    end
  end

  @doc """
  Marks a user's phone as verified by setting the phone_verified_at timestamp.
  """
  def mark_phone_verified(user) do
    case user
         |> User.phone_verification_changeset(%{
           phone_verified_at: DateTime.utc_now()
         })
         |> Repo.update() do
      {:ok, _} = ok ->
        invalidate_user_profile_cache(user)
        ok

      error ->
        error
    end
  end

  @doc """
  Marks a user's password as set by setting the password_set_at timestamp.
  """
  def mark_password_set(user) do
    case user
         |> User.password_set_changeset(%{password_set_at: DateTime.utc_now()})
         |> Repo.update() do
      {:ok, _} = ok ->
        invalidate_user_profile_cache(user)
        ok

      error ->
        error
    end
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
  Returns the first household member (primary or sub-account) who currently
  holds a board position, or `nil` if nobody in the household does.

  Used to determine whether the household's membership billing has been paused
  due to board volunteer service.
  """
  def household_board_member(user) do
    get_family_group(user)
    |> Enum.find(&(&1.board_position != nil))
  end

  @doc """
  Returns a human-readable title for a `BoardMemberPosition` enum value.

  Accepts atoms, valid enum strings, or `nil` (returns `""`).

  ## Examples

      iex> Ysc.Accounts.format_board_position(:vice_president)
      "Vice President"

      iex> Ysc.Accounts.format_board_position("member_outreach")
      "Member Outreach & Events"

      iex> Ysc.Accounts.format_board_position(nil)
      ""

  """
  def format_board_position(nil), do: ""

  def format_board_position(:member_outreach), do: "Member Outreach & Events"

  def format_board_position(position) when is_binary(position) do
    case BoardMemberPosition.cast(position) do
      {:ok, atom} -> format_board_position(atom)
      :error -> String.capitalize(position)
    end
  end

  def format_board_position(position) when is_atom(position) do
    position
    |> to_string()
    |> board_position_title_from_underscores()
  end

  defp board_position_title_from_underscores("member_outreach"),
    do: "Member Outreach & Events"

  defp board_position_title_from_underscores(position) do
    position
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
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
  Admin-only: Links an existing user to a primary user's family membership.

  Bypasses the normal invite flow. Use for manual admin corrections.
  Returns {:ok, user} or {:error, reason}.

  ## Options
  - `:relationship` - :spouse or :child (default: :child)
  """
  def admin_link_user_to_family(primary_user, user_to_link, opts \\ []) do
    relationship = Keyword.get(opts, :relationship, :child)

    cond do
      user_to_link.id == primary_user.id ->
        {:error, :cannot_link_self}

      sub_account?(user_to_link) ->
        {:error, :already_linked_to_family}

      not primary_user?(primary_user) ->
        {:error, :not_primary_user}

      not has_family_or_lifetime_membership?(primary_user) ->
        {:error, :primary_must_have_family_or_lifetime}

      relationship == :spouse ->
        if count_spouses(primary_user) >= 1 do
          {:error, :max_spouses_reached}
        else
          do_admin_link_user(primary_user, user_to_link, relationship)
        end

      count_sub_accounts_for_primary(primary_user.id) >= 10 ->
        {:error, :max_sub_accounts_reached}

      true ->
        do_admin_link_user(primary_user, user_to_link, relationship)
    end
  end

  defp has_family_or_lifetime_membership?(user) do
    has_lifetime_membership?(user) or
      case user.subscriptions do
        %Ecto.Association.NotLoaded{} ->
          subs = Ysc.Subscriptions.list_subscriptions(user)

          Enum.any?(subs, fn s ->
            s = Repo.preload(s, :subscription_items)

            case s.subscription_items do
              [item | _] ->
                plans = Application.get_env(:ysc, :membership_plans, [])

                Enum.any?(plans, fn p ->
                  p.stripe_price_id == item.stripe_price_id and p.id == :family
                end)

              _ ->
                false
            end
          end)

        subs when is_list(subs) ->
          Enum.any?(subs, fn s ->
            s = Repo.preload(s, :subscription_items)

            case s.subscription_items do
              [item | _] ->
                plans = Application.get_env(:ysc, :membership_plans, [])

                Enum.any?(plans, fn p ->
                  p.stripe_price_id == item.stripe_price_id and p.id == :family
                end)

              _ ->
                false
            end
          end)

        _ ->
          false
      end
  end

  defp count_spouses(primary_user) do
    from(u in User,
      where:
        u.primary_user_id == ^primary_user.id and
          u.family_relationship == "spouse"
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_sub_accounts_for_primary(primary_user_id) do
    from(u in User, where: u.primary_user_id == ^primary_user_id)
    |> Repo.aggregate(:count, :id)
  end

  defp do_admin_link_user(primary_user, user_to_link, relationship) do
    Repo.transaction(fn ->
      # Serialize with invite acceptance/linking, which locks the primary row.
      from(u in User, where: u.id == ^primary_user.id, lock: "FOR UPDATE")
      |> Repo.one!()

      case relationship do
        rel when rel in [:spouse, "spouse"] ->
          if count_spouses(primary_user) >= 1 do
            Repo.rollback(:max_spouses_reached)
          end

        _ ->
          if count_sub_accounts_for_primary(primary_user.id) >= 10 do
            Repo.rollback(:max_sub_accounts_reached)
          end
      end

      updated_user =
        user_to_link
        |> Ecto.Changeset.change(%{
          primary_user_id: primary_user.id,
          family_relationship: relationship
        })
        |> Repo.update!()

      %UserEvent{}
      |> UserEvent.new_user_event_changeset(%{
        user_id: updated_user.id,
        updated_by_user_id: primary_user.id,
        type: :family_added,
        from: "none",
        to: "#{primary_user.id}"
      })
      |> Repo.insert!()

      MembershipCache.invalidate_user(updated_user.id)

      invalidate_family_link_profile_caches(
        updated_user.id,
        primary_user.id
      )

      sync_board_volunteer_billing_after_family_change(
        primary_user,
        updated_user
      )

      updated_user
    end)
  end

  @doc """
  Lets a family member (sub-account) leave their family membership from their own dashboard.

  The user becomes independent and can purchase their own membership or join another family later.
  Returns {:ok, updated_user} or {:error, :not_sub_account}.
  """
  @dialyzer {:nowarn_function, leave_family_membership: 1}
  def leave_family_membership(user) do
    if sub_account?(user) do
      primary_user_id = user.primary_user_id
      primary_user = get_primary_user(user)

      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :sub_account,
          user
          |> Ecto.Changeset.change(%{})
          |> Ecto.Changeset.put_change(:primary_user_id, nil)
          |> Ecto.Changeset.put_change(:family_relationship, nil)
        )
        |> Ecto.Multi.insert(
          :user_event,
          UserEvent.new_user_event_changeset(
            %UserEvent{},
            %{
              user_id: user.id,
              updated_by_user_id: user.id,
              type: :family_removed,
              from: "#{primary_user_id}",
              to: "none"
            }
          )
        )

      multi =
        if primary_user do
          YscWeb.Emails.Notifier.schedule_email_multi(
            multi,
            :family_member_removed_email,
            fn _changes ->
              family_member_removed_email_args(user, primary_user)
            end
          )
        else
          multi
        end

      result = Repo.transaction(multi)

      case result do
        {:ok, %{sub_account: updated_sub_account}} ->
          MembershipCache.invalidate_user(updated_sub_account.id)

          invalidate_family_link_profile_caches(
            updated_sub_account.id,
            primary_user_id
          )

          if primary_user do
            sync_board_volunteer_billing_after_family_change(
              primary_user,
              updated_sub_account
            )
          end

          {:ok, updated_sub_account}

        {:error, _, changeset, _} ->
          {:error, changeset}
      end
    else
      {:error, :not_sub_account}
    end
  end

  @doc """
  Removes a sub-account from a family group.
  This makes the sub-account independent (no longer associated with primary).
  """
  @dialyzer {:nowarn_function, remove_sub_account: 2}
  def remove_sub_account(sub_account, primary_user) do
    if sub_account.primary_user_id == primary_user.id do
      result =
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :sub_account,
          sub_account
          |> Ecto.Changeset.change(%{})
          |> Ecto.Changeset.put_change(:primary_user_id, nil)
          |> Ecto.Changeset.put_change(:family_relationship, nil)
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
        |> YscWeb.Emails.Notifier.schedule_email_multi(
          :family_member_removed_email,
          fn _changes ->
            family_member_removed_email_args(sub_account, primary_user)
          end
        )
        |> Repo.transaction()

      case result do
        {:ok, %{sub_account: updated_sub_account}} ->
          MembershipCache.invalidate_user(updated_sub_account.id)

          invalidate_family_link_profile_caches(
            updated_sub_account.id,
            primary_user.id
          )

          sync_board_volunteer_billing_after_family_change(
            primary_user,
            updated_sub_account
          )

          {:ok, updated_sub_account}

        {:error, _, changeset, _} ->
          {:error, changeset}
      end
    else
      {:error, :unauthorized}
    end
  end

  defp invalidate_family_link_profile_caches(user_id, primary_user_id) do
    invalidate_user_profile_cache(user_id)
    invalidate_user_profile_cache(primary_user_id)
  end

  # Family link/unlink changes household_on_board? without touching board_position.
  defp sync_board_volunteer_billing_after_family_change(
         %User{} = primary_user,
         %User{} = affected_user
       ) do
    BoardVolunteerBilling.sync_after_family_membership_change(
      primary_user,
      affected_user
    )
  end

  defp family_member_removed_email_args(removed_user, primary_user) do
    first_name = removed_user.first_name || "there"
    primary_name = primary_user.first_name || "the primary account holder"

    email_vars = %{
      first_name: first_name,
      primary_user_name: primary_name
    }

    idempotency_key =
      "family_member_removed_#{removed_user.id}_#{primary_user.id}"

    %{
      recipient: removed_user.email,
      idempotency_key: idempotency_key,
      subject: "Removed from Family Membership - YSC",
      template: "family_member_removed",
      variables: email_vars,
      text_body: """
      ==============================

      Hi #{first_name},

      You have been removed from #{primary_name}'s family membership.

      You will no longer have access to membership benefits through this family account, including cabin bookings and member event tickets.

      If you would like to continue enjoying YSC membership benefits, you can purchase your own membership at any time.

      ==============================
      """,
      user_id: removed_user.id,
      opts: []
    }
  end

  ## Memberships (admin view)

  @doc """
  Lists all active memberships for admin monitoring.

  A "membership" is a primary user (not a sub-account) with active membership.
  Each membership includes the primary user, type (single/family/lifetime), and
  all associated users (family group).

  ## Options
  - `:type` - Filter by membership type (:single, :family, :lifetime)
  - `:limit` - Max results (default: 100)
  - `:offset` - Pagination offset (default: 0)

  ## Returns
  List of maps: `%{primary_user: user, type: atom, associated_users: [user], user_count: integer}`
  """
  def list_memberships(opts \\ []) do
    opts
    |> active_primary_users_for_memberships()
    |> membership_rows_from_primaries()
  end

  @doc """
  Loads admin membership stats and a paginated membership list.

  Stats always reflect all active memberships; `opts` (`:type`, `:limit`, `:offset`)
  only filter the returned list.

  ## Returns
  `{stats, memberships}` where `stats` matches `get_membership_stats/0` and
  `memberships` matches `list_memberships/1`.
  """
  def load_admin_memberships_page(opts \\ []) do
    {get_membership_stats(), list_memberships(opts)}
  end

  @doc """
  Sortable, searchable, paginated membership list for the admin Memberships
  page, mirroring `list_paginated_users/1,2`.

  `search_term` matches against name/email/phone (via `fuzzy_search_user/2`);
  when present with no explicit sort requested, results rank by match quality
  (same as the Users list) rather than by the default sort below. `opts`
  accepts `:type` to filter by membership type, same as `list_memberships/1`.

  Defaults to sorting by the primary user's current subscription start date
  (newest first) when there's no search term and no explicit sort requested.

  ## Returns
  `{:ok, {membership_rows, meta}}` (same row shape as `list_memberships/1`)
  or `{:error, meta}`.
  """
  def list_paginated_memberships(params, search_term \\ nil, opts \\ [])

  def list_paginated_memberships(params, nil, opts),
    do: list_paginated_memberships_without_search(params, opts)

  def list_paginated_memberships(params, search_term, opts)
      when search_term == "",
      do: list_paginated_memberships_without_search(params, opts)

  def list_paginated_memberships(params, search_term, opts) do
    now = DateTime.utc_now()

    {application_date_sort, other_params} =
      extract_application_date_sort(params)

    {subscription_start_sort, other_params} =
      extract_subscription_start_sort(other_params)

    has_explicit_sort =
      explicit_sort?(other_params) or application_date_sort != nil or
        subscription_start_sort != nil

    base_query =
      fuzzy_search_user(search_term, rank: !has_explicit_sort)
      |> active_membership_primary_user_filter(now)
      |> apply_membership_type_filter(Keyword.get(opts, :type))
      |> apply_application_date_order_by(application_date_sort, now)
      |> apply_subscription_start_order_by(subscription_start_sort, now)

    finish_paginated_memberships(
      base_query,
      other_params,
      application_date_sort,
      subscription_start_sort
    )
  end

  defp list_paginated_memberships_without_search(params, opts) do
    now = DateTime.utc_now()
    params = maybe_default_order(params, "subscription_start")

    {application_date_sort, other_params} =
      extract_application_date_sort(params)

    {subscription_start_sort, other_params} =
      extract_subscription_start_sort(other_params)

    base_query =
      from(u in User, where: u.state != :deleted)
      |> active_membership_primary_user_filter(now)
      |> apply_membership_type_filter(Keyword.get(opts, :type))
      |> apply_application_date_order_by(application_date_sort, now)
      |> apply_subscription_start_order_by(subscription_start_sort, now)

    finish_paginated_memberships(
      base_query,
      other_params,
      application_date_sort,
      subscription_start_sort
    )
  end

  defp finish_paginated_memberships(
         base_query,
         other_params,
         application_date_sort,
         subscription_start_sort
       ) do
    case Flop.validate_and_run(base_query, other_params, for: User) do
      {:ok, {primary_users, meta}} ->
        meta =
          meta
          |> restore_application_date_sort(application_date_sort)
          |> restore_subscription_start_sort(subscription_start_sort)

        primary_users =
          Repo.preload(primary_users, [
            {:sub_accounts, :current_avatar},
            :current_avatar,
            :registration_form,
            subscriptions: :subscription_items
          ])

        {:ok, {membership_rows_from_primaries(primary_users), meta}}

      error ->
        error
    end
  end

  @doc """
  Returns membership counts by type for admin dashboard.

  Uses SQL `COUNT` queries instead of loading every active primary user.

  ## Returns
  `%{total: integer, single: integer, family: integer, lifetime: integer}`
  """
  def get_membership_stats do
    base = active_membership_primary_users_query()
    family_price_id = family_membership_price_id()

    %{total: total, lifetime: lifetime, family: family} =
      if family_price_id do
        family_sub = active_family_membership_user_ids_query(family_price_id)

        from(u in base,
          select: %{
            total: count(u.id),
            lifetime:
              count(u.id)
              |> filter(not is_nil(u.lifetime_membership_awarded_at)),
            family:
              count(u.id)
              |> filter(
                is_nil(u.lifetime_membership_awarded_at) and
                  u.id in subquery(family_sub)
              )
          }
        )
        |> Repo.one()
      else
        from(u in base,
          select: %{
            total: count(u.id),
            lifetime:
              count(u.id)
              |> filter(not is_nil(u.lifetime_membership_awarded_at)),
            family: type(^0, :integer)
          }
        )
        |> Repo.one()
      end

    %{
      total: total,
      single: total - lifetime - family,
      family: family,
      lifetime: lifetime
    }
  end

  # Composable so it can be layered on top of a plain `User` query or a
  # fuzzy-search query (see list_paginated_memberships/3).
  defp active_membership_primary_user_filter(query, now) do
    valid_subscription_user_ids =
      from(s in Subscription,
        where: s.stripe_status in ["active", "trialing"],
        where: s.current_period_end > ^now,
        where: is_nil(s.ends_at) or s.ends_at > ^now,
        select: s.user_id,
        distinct: true
      )

    from(u in query,
      where: is_nil(u.primary_user_id),
      where: u.state == :active,
      where:
        not is_nil(u.lifetime_membership_awarded_at) or
          u.id in subquery(valid_subscription_user_ids)
    )
  end

  defp active_membership_primary_users_query do
    active_membership_primary_user_filter(from(u in User), DateTime.utc_now())
  end

  # Helper function to extract subscription_start sorting from params.
  # Mirrors extract_application_date_sort/1 - the primary user's current
  # (active) subscription start, used as the Membership admin list's default
  # sort.
  defp extract_subscription_start_sort(params) do
    case params do
      %{"order_by" => order_by, "order_directions" => order_directions}
      when is_list(order_by) and is_list(order_directions) ->
        sort_index = Enum.find_index(order_by, &(&1 == "subscription_start"))

        if sort_index do
          direction =
            order_directions
            |> Enum.at(sort_index, "asc")
            |> then(fn
              "desc" -> :desc
              _ -> :asc
            end)

          new_order_by = List.delete_at(order_by, sort_index)

          new_order_directions =
            List.delete_at(order_directions, sort_index)

          new_params =
            params
            |> Map.put("order_by", new_order_by)
            |> Map.put("order_directions", new_order_directions)

          {{:subscription_start, direction, sort_index}, new_params}
        else
          {nil, params}
        end

      _ ->
        {nil, params}
    end
  end

  defp apply_subscription_start_order_by(query, nil, _now), do: query

  # Lifetime members with no billed subscription have no current_period_start,
  # so nulls sort last regardless of direction (same rule agreed for
  # application_date, though that field never actually goes nil).
  defp apply_subscription_start_order_by(
         query,
         {:subscription_start, direction, _index},
         now
       ) do
    joined =
      from u in query,
        left_join:
          css in subquery(current_active_subscription_start_subquery(now)),
        on: css.user_id == u.id

    case direction do
      :asc ->
        from [u, css] in joined,
          order_by: [asc_nulls_last: css.subscription_start]

      :desc ->
        from [u, css] in joined,
          order_by: [desc_nulls_last: css.subscription_start]
    end
  end

  # MAX(current_period_start) per user matches "latest active subscription"
  # (ORDER BY current_period_start DESC LIMIT 1) when multiple rows exist.
  defp current_active_subscription_start_subquery(now) do
    from(s in Subscription,
      where: s.stripe_status in ["active", "trialing"],
      where: s.current_period_end > ^now,
      where: is_nil(s.ends_at) or s.ends_at > ^now,
      group_by: s.user_id,
      select: %{
        user_id: s.user_id,
        subscription_start: max(s.current_period_start)
      }
    )
  end

  defp restore_subscription_start_sort(meta, nil), do: meta

  defp restore_subscription_start_sort(
         %Flop.Meta{} = meta,
         {:subscription_start, direction, index}
       ) do
    current_order_by = meta.flop.order_by || []
    current_directions = meta.flop.order_directions || []

    safe_index = min(index, length(current_order_by))

    updated_flop = %{
      meta.flop
      | order_by:
          List.insert_at(current_order_by, safe_index, :subscription_start),
        order_directions:
          List.insert_at(current_directions, safe_index, direction)
    }

    %{meta | flop: updated_flop}
  end

  defp active_family_membership_user_ids_query(family_price_id) do
    now = DateTime.utc_now()

    from(si in SubscriptionItem,
      join: s in Subscription,
      on: si.subscription_id == s.id,
      where: s.stripe_status in ["active", "trialing"],
      where: s.current_period_end > ^now,
      where: is_nil(s.ends_at) or s.ends_at > ^now,
      where: si.stripe_price_id == ^family_price_id,
      select: s.user_id,
      distinct: true
    )
  end

  defp family_membership_price_id do
    Application.get_env(:ysc, :membership_plans, [])
    |> Enum.find_value(fn plan ->
      if plan.id == :family, do: plan.stripe_price_id
    end)
  end

  defp apply_membership_type_filter(query, nil), do: query

  defp apply_membership_type_filter(query, :lifetime) do
    from(u in query, where: not is_nil(u.lifetime_membership_awarded_at))
  end

  defp apply_membership_type_filter(query, :family) do
    case family_membership_price_id() do
      nil ->
        from(u in query, where: false)

      family_price_id ->
        from(u in query,
          where: is_nil(u.lifetime_membership_awarded_at),
          where:
            u.id in subquery(
              active_family_membership_user_ids_query(family_price_id)
            )
        )
    end
  end

  defp apply_membership_type_filter(query, :single) do
    case family_membership_price_id() do
      nil ->
        from(u in query, where: is_nil(u.lifetime_membership_awarded_at))

      family_price_id ->
        from(u in query,
          where: is_nil(u.lifetime_membership_awarded_at),
          where:
            u.id not in subquery(
              active_family_membership_user_ids_query(family_price_id)
            )
        )
    end
  end

  defp active_primary_users_for_memberships(opts) do
    type_filter = Keyword.get(opts, :type)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    active_membership_primary_users_query()
    |> apply_membership_type_filter(type_filter)
    |> order_by([u], asc: u.last_name, asc: u.first_name)
    |> limit(^limit)
    |> offset(^offset)
    |> preload([
      {:sub_accounts, :current_avatar},
      :current_avatar,
      subscriptions: :subscription_items
    ])
    |> Repo.all()
  end

  defp membership_rows_from_primaries(primary_users) do
    primary_users
    |> Enum.map(fn primary ->
      associated = get_family_group(primary)

      %{
        primary_user: primary,
        type: get_membership_type_for_primary(primary),
        associated_users: associated,
        user_count: length(associated)
      }
    end)
  end

  # Below this, a YoY percent change is too noisy to be meaningful (e.g. a
  # prior-period count of 1 turns any uptick into a four-or-five-digit swing)
  # and is hidden in favor of the raw counts already shown alongside it.
  @membership_joins_change_percent_min_baseline 5

  @doc """
  YTD comparison of **new membership joins** (not active headcount).

  Counts distinct primary `User` accounts that either:

  - had `lifetime_membership_awarded_at` fall in the half-open interval
    `[range_start, range_end)`, or
  - had their **first** ever `Subscription` that reached a paid status
    (i.e. excluding "incomplete"/"incomplete_expired" checkout attempts
    that never converted) fall in that interval, by `inserted_at`.

  Used on the admin dashboard to compare this year-to-date with the same
  calendar-aligned span last year (Jan 1 through the same instant, shifted back one year).
  """
  def get_membership_joins_ytd_comparison do
    %DateTime{} = now = DateTime.utc_now() |> DateTime.truncate(:second)

    year_start = %DateTime{
      now
      | month: 1,
        day: 1,
        hour: 0,
        minute: 0,
        second: 0,
        microsecond: {0, 0}
    }

    prior_period_end = Timex.shift(now, years: -1)
    prior_year_start = Timex.shift(year_start, years: -1)

    current_count = membership_joins_in_interval(year_start, now)

    prior_count =
      membership_joins_in_interval(prior_year_start, prior_period_end)

    %DateTime{year: prior_year} =
      DateTime.shift_zone!(prior_year_start, "America/Los_Angeles")

    prior_year_label = Integer.to_string(prior_year)

    change_percent =
      if prior_count >= @membership_joins_change_percent_min_baseline do
        round((current_count - prior_count) / prior_count * 100)
      else
        nil
      end

    %{
      current_ytd_joins: current_count,
      prior_ytd_joins: prior_count,
      prior_year_label: prior_year_label,
      joins_ytd_change_percent: change_percent
    }
  end

  defp membership_joins_in_interval(
         %DateTime{} = start_dt,
         %DateTime{} = end_dt
       ) do
    lifetime_ids =
      from(u in User,
        where: is_nil(u.primary_user_id),
        where: u.state == :active,
        where: not is_nil(u.lifetime_membership_awarded_at),
        where:
          u.lifetime_membership_awarded_at >= ^start_dt and
            u.lifetime_membership_awarded_at < ^end_dt,
        select: u.id
      )
      |> Repo.all()

    first_sub_q =
      from(s in Subscription,
        join: u in User,
        on: s.user_id == u.id,
        where: is_nil(u.primary_user_id),
        where: u.state == :active,
        where: s.stripe_status not in ["incomplete", "incomplete_expired"],
        group_by: u.id,
        select: %{user_id: u.id, first_at: min(s.inserted_at)}
      )

    sub_ids =
      from(f in subquery(first_sub_q),
        where: f.first_at >= ^start_dt and f.first_at < ^end_dt,
        select: f.user_id
      )
      |> Repo.all()

    (lifetime_ids ++ sub_ids) |> Enum.uniq() |> length()
  end

  defp get_membership_type_for_primary(user) do
    if has_lifetime_membership?(user) do
      :lifetime
    else
      subscriptions =
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            Ysc.Subscriptions.list_subscriptions(user)

          subscriptions when is_list(subscriptions) ->
            subscriptions

          _ ->
            []
        end

      active =
        subscriptions
        |> Enum.filter(&Ysc.Subscriptions.valid?/1)

      case active do
        [] ->
          :single

        [sub | _] ->
          membership_plans = Application.get_env(:ysc, :membership_plans, [])

          price_to_type =
            Map.new(membership_plans, fn p -> {p.stripe_price_id, p.id} end)

          sub =
            if Ecto.assoc_loaded?(sub.subscription_items) do
              sub
            else
              Repo.preload(sub, :subscription_items)
            end

          case sub.subscription_items do
            [item | _] ->
              Map.get(price_to_type, item.stripe_price_id, :single)

            _ ->
              :single
          end
      end
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

  @doc """
  Lists user notes filtered by category (e.g. :rejection).

  Returns notes ordered by most recent first, with created_by preloaded.
  """
  def list_user_notes_by_category(user_id, category) do
    from(n in UserNote,
      where: n.user_id == ^user_id and n.category == ^category,
      order_by: [desc: n.inserted_at],
      preload: [:created_by]
    )
    |> Repo.all()
  end

  ## Post-migration onboarding

  @doc """
  Returns true when a user needs to complete the post-migration onboarding wizard.

  Conditions:
  - The user has not yet completed onboarding (`post_migration_onboarding_completed_at` is nil)
  - The user has finished account setup (email verified)
  - The user's account is active (not pending approval or suspended)
  """
  def needs_post_migration_onboarding?(%User{} = user) do
    is_nil(user.post_migration_onboarding_completed_at) and
      not is_nil(user.email_verified_at) and
      user.state == :active
  end

  @doc """
  Marks the post-migration onboarding as complete for a user.
  """
  def complete_post_migration_onboarding(%User{} = user) do
    user
    |> Ecto.Changeset.change(
      post_migration_onboarding_completed_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update()
  end

  @doc """
  Returns true when a user's account originated from the WordPress migration
  rather than the normal application → registration flow.

  `register_user/1` sets `post_migration_onboarding_completed_at` immediately
  for every native sign-up; WP-migrated users are inserted directly via
  `User.registration_changeset/2` and are left with this field `nil`, so its
  absence is a permanent (not just migration-window) marker of a migrated
  account.
  """
  def wp_migrated?(%User{} = user) do
    is_nil(user.post_migration_onboarding_completed_at)
  end

  @doc false
  def ci_query_explain_query do
    from(u in User,
      where: u.state != :deleted,
      order_by: [asc: u.last_name, asc: u.first_name],
      limit: 50
    )
  end
end
