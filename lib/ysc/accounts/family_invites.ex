defmodule Ysc.Accounts.FamilyInvites do
  @moduledoc """
  The FamilyInvites context.

  Handles creation, validation, and acceptance of family member invites.
  """
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Accounts.{User, FamilyInvite, UserEvent}
  alias YscWeb.Emails.Notifier

  @max_sub_accounts 10

  @doc """
  Creates a family invite for the given primary user.

  Validates that:
  - Primary user is active
  - Primary user has family or lifetime membership
  - Primary user has less than 10 sub-accounts
  - Email is not already a user
  - Email doesn't have a pending invite from this primary user

  Returns {:ok, invite} or {:error, reason}

  ## Options
  - `family_member_id` - Optional ID of a family member from registration form to include in email
  """
  def create_invite(primary_user, email, opts \\ []) do
    family_member_id = Keyword.get(opts, :family_member_id)

    with :ok <- validate_primary_user_eligibility(primary_user),
         :ok <- validate_email_available(email, primary_user.id),
         :ok <- validate_no_pending_invite(email, primary_user.id) do
      token = FamilyInvite.build_token()

      attrs = %{
        email: email,
        token: token,
        primary_user_id: primary_user.id,
        created_by_user_id: primary_user.id
      }

      case %FamilyInvite{}
           |> FamilyInvite.changeset(attrs)
           |> Repo.insert() do
        {:ok, invite} ->
          opts =
            if family_member_id,
              do: [family_member_id: family_member_id],
              else: []

          send_invite_email(invite, primary_user, opts)
          {:ok, invite}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Gets an invite by token.
  """
  def get_invite_by_token(token) do
    Repo.get_by(FamilyInvite, token: token)
    |> Repo.preload([:primary_user, :created_by_user])
  end

  @doc """
  Accepts a family invite and creates a sub-account user.

  Returns {:ok, user} or {:error, reason}
  """
  def accept_invite(token, user_attrs) do
    invite = get_invite_by_token(token)

    cond do
      is_nil(invite) ->
        {:error, :invite_not_found}

      not FamilyInvite.valid?(invite) ->
        {:error, :invite_expired_or_used}

      true ->
        Repo.transaction(fn ->
          # Create sub-account user
          case %User{}
               |> User.sub_account_registration_changeset(
                 user_attrs,
                 invite.primary_user_id,
                 hash_password: true,
                 validate_email: true
               )
               |> Repo.insert() do
            {:ok, user} ->
              # Mark invite as accepted
              invite
              |> FamilyInvite.accept_changeset()
              |> Repo.update!()

              # Mark email as verified (email was verified by primary user when sending invite)
              # and ensure password_set_at is set if password was provided
              now = DateTime.utc_now() |> DateTime.truncate(:second)
              update_attrs = %{email_verified_at: now}

              # Ensure password_set_at is set if password was provided but wasn't set by changeset
              update_attrs =
                if is_nil(user.password_set_at) &&
                     not is_nil(user.hashed_password) do
                  Map.put(update_attrs, :password_set_at, now)
                else
                  update_attrs
                end

              # Update user with verification and password_set_at
              updated_user =
                user
                |> Ecto.Changeset.change(update_attrs)
                |> Repo.update!()

              # Copy billing address from primary user
              copy_billing_address_from_primary(
                updated_user,
                invite.primary_user_id
              )

              # Copy most_connected_country from primary user if not already set
              final_user =
                copy_most_connected_country_from_primary(
                  updated_user,
                  invite.primary_user_id
                )

              # Create UserEvent to track family addition
              %UserEvent{}
              |> UserEvent.new_user_event_changeset(%{
                user_id: updated_user.id,
                updated_by_user_id: invite.primary_user_id,
                type: :family_added,
                from: "none",
                to: "#{invite.primary_user_id}"
              })
              |> Repo.insert!()

              # Create Stripe customer asynchronously
              Task.start(fn ->
                is_test = Ysc.Env.test?()

                if is_test do
                  owner =
                    Ysc.Repo.config()[:owner] ||
                      Process.get({Ecto.Adapters.SQL.Sandbox, :owner})

                  if owner do
                    Ecto.Adapters.SQL.Sandbox.allow(Ysc.Repo, self(), owner)
                  else
                    Ecto.Adapters.SQL.Sandbox.checkout(Ysc.Repo, sandbox: true)
                  end
                end

                # Wrap in try-catch to suppress errors in test mode
                try do
                  Ysc.Customers.create_stripe_customer(updated_user)
                rescue
                  e ->
                    # In test mode, silently ignore errors to keep test output clean
                    unless is_test do
                      require Logger

                      Logger.error(
                        "Failed to create Stripe customer in background task",
                        user_id: updated_user.id,
                        error: Exception.format(:error, e, __STACKTRACE__)
                      )
                    end
                catch
                  kind, reason ->
                    # Catch all other errors (throws, exits, etc.)
                    unless is_test do
                      require Logger

                      Logger.error(
                        "Failed to create Stripe customer in background task",
                        user_id: updated_user.id,
                        kind: kind,
                        reason: inspect(reason)
                      )
                    end
                end
              end)

              final_user

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
    end
  end

  @doc """
  Lists all invites for a primary user (pending and accepted).
  """
  def list_invites(primary_user) do
    from(i in FamilyInvite,
      where: i.primary_user_id == ^primary_user.id,
      order_by: [desc: i.inserted_at],
      preload: [:created_by_user]
    )
    |> Repo.all()
  end

  @doc """
  Revokes a pending invite.

  Only the primary user who created the invite can revoke it.
  """
  def revoke_invite(invite_id, primary_user) do
    invite = Repo.get(FamilyInvite, invite_id)

    cond do
      is_nil(invite) ->
        {:error, :not_found}

      invite.primary_user_id != primary_user.id ->
        {:error, :unauthorized}

      not is_nil(invite.accepted_at) ->
        {:error, :already_accepted}

      true ->
        Repo.delete(invite)
    end
  end

  @doc """
  Validates that a user is eligible to send family invites.

  Returns :ok if eligible, {:error, reason} otherwise.
  """
  def validate_primary_user_eligibility(user) do
    cond do
      user.state != :active ->
        {:error, :user_not_active}

      not has_family_or_lifetime_membership?(user) ->
        {:error, :invalid_membership_type}

      count_sub_accounts(user) >= @max_sub_accounts ->
        {:error, :max_sub_accounts_reached}

      true ->
        :ok
    end
  end

  @doc """
  Checks if a user can send family invites.
  """
  def can_send_family_invite?(user) do
    case validate_primary_user_eligibility(user) do
      :ok -> true
      _ -> false
    end
  end

  # Private functions

  defp has_family_or_lifetime_membership?(user) do
    if Ysc.Accounts.has_lifetime_membership?(user) do
      true
    else
      # Check if user has family membership
      subscriptions =
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            Ysc.Subscriptions.list_subscriptions(user)

          subscriptions when is_list(subscriptions) ->
            subscriptions

          _ ->
            []
        end

      active_subscriptions =
        Enum.filter(subscriptions, fn sub ->
          Ysc.Subscriptions.valid?(sub)
        end)

      Enum.any?(active_subscriptions, fn subscription ->
        subscription = Ysc.Repo.preload(subscription, :subscription_items)

        case subscription.subscription_items do
          [item | _] ->
            membership_plans = Application.get_env(:ysc, :membership_plans, [])

            Enum.any?(membership_plans, fn plan ->
              plan.stripe_price_id == item.stripe_price_id && plan.id == :family
            end)

          _ ->
            false
        end
      end)
    end
  end

  defp count_sub_accounts(primary_user) do
    from(u in User,
      where: u.primary_user_id == ^primary_user.id
    )
    |> Repo.aggregate(:count, :id)
  end

  defp validate_email_available(email, primary_user_id) do
    existing_user = Ysc.Accounts.get_user_by_email(email)

    if existing_user && existing_user.id != primary_user_id do
      {:error, :email_already_registered}
    else
      :ok
    end
  end

  defp validate_no_pending_invite(email, primary_user_id) do
    pending_invite =
      from(i in FamilyInvite,
        where: i.email == ^email,
        where: i.primary_user_id == ^primary_user_id,
        where: is_nil(i.accepted_at),
        where: i.expires_at > ^DateTime.utc_now()
      )
      |> Repo.one()

    if pending_invite do
      {:error, :pending_invite_exists}
    else
      :ok
    end
  end

  defp send_invite_email(invite, primary_user, opts) do
    family_member_id = Keyword.get(opts, :family_member_id)

    # Get family member info if provided
    family_member_name =
      if family_member_id && family_member_id != "" do
        case get_family_member_name(primary_user, family_member_id) do
          {:ok, name} -> name
          _ -> nil
        end
      else
        nil
      end

    base_url = Application.get_env(:ysc, :base_url) || "http://localhost:4000"
    invite_url = "#{base_url}/family-invite/#{invite.token}/accept"

    idempotency_key = "family_invite_#{invite.id}"

    # Include family member name in email variables if available
    email_vars = %{
      primary_user_name: primary_user.first_name,
      invite_url: invite_url,
      expires_in_days: 30,
      family_member_name: family_member_name
    }

    Notifier.schedule_email(
      invite.email,
      idempotency_key,
      "You're Invited to Join #{primary_user.first_name}'s Family Membership - YSC",
      "family_invite",
      email_vars,
      """
      ==============================

      Hi#{if family_member_name, do: " #{family_member_name}", else: " there"},

      #{primary_user.first_name} has invited you to join their YSC family membership!

      Click the link below to create your account and start enjoying all the benefits:

      #{invite_url}

      This invite will expire in 30 days.

      ==============================
      """,
      primary_user.id
    )
  end

  defp get_family_member_name(primary_user, family_member_id) do
    # Load user with family members
    user =
      if Ecto.assoc_loaded?(primary_user.family_members) do
        primary_user
      else
        Ysc.Accounts.get_user!(primary_user.id, [:family_members])
      end

    if Ecto.assoc_loaded?(user.family_members) do
      find_and_format_family_member_name(user.family_members, family_member_id)
    else
      {:error, :family_members_not_loaded}
    end
  end

  defp find_and_format_family_member_name(family_members, family_member_id) do
    case Enum.find(family_members, &(&1.id == family_member_id)) do
      %Ysc.Accounts.FamilyMember{first_name: first_name, last_name: last_name}
      when not is_nil(first_name) ->
        name = format_family_member_name(first_name, last_name)
        {:ok, name}

      _ ->
        {:error, :not_found}
    end
  end

  defp format_family_member_name(first_name, last_name) do
    if last_name do
      "#{first_name} #{last_name}"
    else
      first_name
    end
  end

  defp copy_billing_address_from_primary(sub_account, primary_user_id) do
    primary_user = Ysc.Accounts.get_user!(primary_user_id, [:billing_address])

    case primary_user.billing_address do
      %Ysc.Accounts.Address{} = primary_address ->
        # Check if sub-account already has an address
        existing_address =
          Ysc.Repo.get_by(Ysc.Accounts.Address, user_id: sub_account.id)

        if existing_address do
          {:ok, existing_address}
        else
          create_billing_address_for_sub_account(
            sub_account,
            primary_user_id,
            primary_address
          )
        end

      _ ->
        # Primary user doesn't have a billing address, skip
        {:ok, nil}
    end
  end

  defp copy_most_connected_country_from_primary(sub_account, primary_user_id) do
    primary_user = Ysc.Accounts.get_user!(primary_user_id)

    # Only copy if primary user has a most_connected_country and sub-account doesn't
    if not is_nil(primary_user.most_connected_country) and
         is_nil(sub_account.most_connected_country) do
      sub_account
      |> Ecto.Changeset.change(
        most_connected_country: primary_user.most_connected_country
      )
      |> Repo.update!()
    else
      sub_account
    end
  end

  defp create_billing_address_for_sub_account(
         sub_account,
         primary_user_id,
         primary_address
       ) do
    # Copy address fields from primary user
    address_attrs = %{
      address: primary_address.address,
      city: primary_address.city,
      region: primary_address.region,
      postal_code: primary_address.postal_code,
      country: primary_address.country,
      user_id: sub_account.id
    }

    case Ysc.Accounts.Address.changeset(%Ysc.Accounts.Address{}, address_attrs)
         |> Ysc.Repo.insert() do
      {:ok, address} ->
        {:ok, address}

      {:error, changeset} ->
        require Logger

        Logger.warning("Failed to copy billing address for sub-account",
          user_id: sub_account.id,
          primary_user_id: primary_user_id,
          errors: inspect(changeset.errors)
        )

        {:ok, nil}
    end
  end
end
