defmodule Ysc.Accounts.FamilyInvites do
  @moduledoc """
  The FamilyInvites context.

  Handles creation, validation, and acceptance of family member invites.
  """
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ecto.Multi

  alias Ysc.Accounts.{
    Address,
    Email,
    User,
    FamilyInvite,
    FamilyMember,
    UserEvent,
    UserProfileCache
  }

  alias Ysc.Subscriptions.BoardVolunteerBilling
  alias YscWeb.Emails.Notifier

  @max_sub_accounts 10
  @max_spouses 1
  @adult_age 18

  # Invite pages, membership pending-invite cards, and the accepted-invite
  # email only need identity + country. Skip hashed_password / board_bio /
  # Stripe ids that `preload([:primary_user, :created_by_user])` would SELECT.
  @invite_user_fields [
    :id,
    :first_name,
    :last_name,
    :email,
    :most_connected_country
  ]

  @doc """
  Toast shown when an invitation token does not match a current invite.

  Cancelled invites are deleted, so clicking the original email button lands
  here rather than on an "expired" message.
  """
  def missing_invite_message do
    "This invitation is no longer valid."
  end

  @doc """
  Returns true when someone born on `birth_date` is #{@adult_age} or older on `today`.

  Children who are adults cannot join a family membership; they need their own
  account and membership. Unknown birth dates are not treated as adult.
  """
  def adult?(birth_date, today \\ Date.utc_today())

  def adult?(%Date{} = birth_date, %Date{} = today) do
    Date.compare(Date.shift(birth_date, year: @adult_age), today) != :gt
  end

  def adult?(_birth_date, _today), do: false

  @doc """
  Message shown when a child invite is refused because the child is an adult.
  """
  def child_is_adult_message(name \\ nil)

  def child_is_adult_message(name) when is_binary(name) and name != "" do
    "#{name} is #{@adult_age} or older, so they can't be added to a family membership. " <>
      "Adults need their own YSC account and membership."
  end

  def child_is_adult_message(_name) do
    "Children who are #{@adult_age} or older can't be added to a family membership. " <>
      "Adults need their own YSC account and membership."
  end

  @doc """
  Adds a `:date_of_birth` error to a sub-account registration changeset when a
  child invite is being accepted by someone who is #{@adult_age} or older.
  """
  def validate_child_age(
        %Ecto.Changeset{} = changeset,
        %FamilyInvite{} = invite
      ) do
    date_of_birth = Ecto.Changeset.get_field(changeset, :date_of_birth)

    if child_invite?(invite) and adult?(date_of_birth) do
      Ecto.Changeset.add_error(
        changeset,
        :date_of_birth,
        "must be under #{@adult_age} to join as a child. Adults need their own YSC account and membership"
      )
    else
      changeset
    end
  end

  @doc """
  Changeset for the date of birth an existing account must give before
  linking to a child invite (required, plausible, and under #{@adult_age}).
  """
  def link_date_of_birth_changeset(
        %User{} = user,
        %FamilyInvite{} = invite,
        attrs \\ %{}
      ) do
    user
    |> User.date_of_birth_changeset(attrs)
    |> validate_child_age(invite)
  end

  @doc """
  True when `user` must supply a date of birth before linking to `invite`:
  child invites need one so the under-#{@adult_age} rule can be checked.
  """
  def date_of_birth_required_to_link?(%User{} = user, %FamilyInvite{} = invite),
    do: child_invite?(invite) and is_nil(user.date_of_birth)

  @doc """
  Returns true when the invite adds the invitee as a child (the default).
  """
  def child_invite?(%FamilyInvite{relationship: relationship}),
    do: child_relationship?(relationship)

  defp child_relationship?(relationship),
    do: relationship not in [:spouse, "spouse"]

  @doc """
  Creates a family invite for the given primary user.

  Validates that:
  - Primary user is active
  - Primary user has family or lifetime membership
  - Primary user has less than 10 sub-accounts
  - Max 1 spouse (when relationship is :spouse)
  - A child listed in the family roster (`family_member_id`) is under 18
  - Email doesn't have a pending invite from this primary user
  - Email is not already registered to another user (use Accounts.admin_link_user_to_family/3
    for directly linking existing users without an invite)

  Returns {:ok, invite} or {:error, reason}

  ## Options
  - `family_member_id` - Optional ID of a family member from registration form to include in email
  - `relationship` - Either :spouse or :child (default). Max 1 spouse per family.
    Ignored when `family_member_id` matches a roster member; their stored type is used.
  """
  @dialyzer {:nowarn_function, create_invite: 3}
  def create_invite(primary_user, email, opts \\ []) do
    family_member_id = Keyword.get(opts, :family_member_id)
    family_member = get_family_member(primary_user, family_member_id)

    # A roster member's stored type wins over the option, so a caller can't
    # invite an adult child as a "spouse" to skip the age check.
    relationship =
      case family_member do
        %FamilyMember{type: :spouse} -> :spouse
        %FamilyMember{} -> :child
        nil -> Keyword.get(opts, :relationship, :child)
      end

    with :ok <- validate_primary_user_eligibility(primary_user),
         :ok <- validate_child_not_adult(relationship, family_member),
         :ok <- validate_relationship_limits(primary_user, relationship),
         :ok <- validate_email_not_registered(email, primary_user.id),
         :ok <- validate_no_pending_invite(email, primary_user.id) do
      token = FamilyInvite.build_token()

      attrs = %{
        email: String.downcase(String.trim(email)),
        token: token,
        primary_user_id: primary_user.id,
        created_by_user_id: primary_user.id,
        relationship: relationship
      }

      Multi.new()
      |> Multi.insert(:invite, FamilyInvite.changeset(%FamilyInvite{}, attrs))
      |> Notifier.schedule_email_multi(:invite_email, fn %{invite: invite} ->
        invite_email_attrs(invite, primary_user, family_member)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{invite: invite}} ->
          {:ok, invite}

        {:error, :invite, changeset, _changes} ->
          {:error, changeset}

        {:error, _operation, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Gets an invite by token.

  Loads slim `primary_user` (name, email, country) and `created_by_user`
  (name, email) for the accept page and the accepted-invite email. The family
  settings list does not use this helper.
  """
  def get_invite_by_token(token) do
    token
    |> get_invite_by_token_query()
    |> Repo.one()
  end

  @doc """
  Locks the primary account and validates a family invite can still be accepted.

  Must run inside the same database transaction as the accept/link update.
  Returns `:ok` or `{:error, reason}`.
  """
  def validate_invite_acceptance(repo, %FamilyInvite{} = invite) do
    primary_user_id = invite.primary_user_id
    relationship = invite.relationship || :child

    nested_primary_id =
      from(u in User,
        where: u.id == ^primary_user_id,
        select: u.primary_user_id,
        lock: "FOR UPDATE"
      )
      |> repo.one!()

    cond do
      # Finding 83: nested invites must not be accepted even if they were
      # persisted before create_invite started refusing sub-accounts.
      not is_nil(nested_primary_id) ->
        {:error, :not_primary_user}

      not FamilyInvite.valid?(invite) ->
        {:error, :invite_expired_or_used}

      count_sub_accounts_by_primary_id(primary_user_id) >= @max_sub_accounts ->
        {:error, :max_sub_accounts_reached}

      relationship in [:spouse, "spouse"] and
          count_spouses(%User{id: primary_user_id}) >= @max_spouses ->
        {:error, :max_spouses_reached}

      true ->
        :ok
    end
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

      not invite_email_matches_attrs?(invite, user_attrs) ->
        {:error, :email_mismatch}

      true ->
        Repo.transaction(fn ->
          case validate_invite_acceptance(Repo, invite) do
            :ok -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end

          # Create sub-account user
          case %User{}
               |> User.sub_account_registration_changeset(
                 user_attrs,
                 invite.primary_user_id,
                 hash_password: true,
                 validate_email: true
               )
               |> validate_child_age(invite)
               |> Repo.insert() do
            {:ok, user} ->
              # Set family_relationship from invite
              relationship = invite.relationship || :child

              # Mark invite as accepted
              invite
              |> FamilyInvite.accept_changeset()
              |> Repo.update!()

              # Mark email as verified (email was verified by primary user when sending invite)
              # and ensure password_set_at is set if password was provided
              now = DateTime.utc_now() |> DateTime.truncate(:second)

              update_attrs = %{
                email_verified_at: now,
                family_relationship: relationship
              }

              # Ensure password_set_at is set if password was provided but wasn't set by changeset
              update_attrs =
                if is_nil(user.password_set_at) &&
                     not is_nil(user.hashed_password) do
                  Map.put(update_attrs, :password_set_at, now)
                else
                  update_attrs
                end

              # Update user with verification, password_set_at, and family_relationship
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
                  invite.primary_user
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
                    if !is_test do
                      require Ysc.Logging

                      Ysc.Logging.error(
                        "Failed to create Stripe customer in background task",
                        user_id: updated_user.id,
                        error: Exception.format(:error, e, __STACKTRACE__)
                      )
                    end
                catch
                  kind, reason ->
                    # Catch all other errors (throws, exits, etc.)
                    if !is_test do
                      require Ysc.Logging

                      Ysc.Logging.error(
                        "Failed to create Stripe customer in background task",
                        user_id: updated_user.id,
                        kind: kind,
                        reason: inspect(reason)
                      )
                    end
                end
              end)

              schedule_invite_accepted_email!(invite, final_user)

              final_user

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
        |> case do
          {:ok, final_user} = ok ->
            invalidate_family_link_profile_caches(
              final_user.id,
              invite.primary_user_id
            )

            sync_board_volunteer_billing_after_family_change(
              invite.primary_user_id,
              final_user.id
            )

            ok

          error ->
            error
        end
    end
  end

  @doc """
  Links an existing user to a family membership via invite.

  The user must be logged in and their email must match the invite.

  Child invites are only for under-#{@adult_age}s. When the account has no
  date of birth on file, pass one in `attrs` (`"date_of_birth"`); it is
  validated and saved on the account as part of the link.

  Returns {:ok, user} or {:error, reason}, where reason may be
  `:date_of_birth_required`, `:child_is_adult`, or an `Ecto.Changeset` with a
  `:date_of_birth` error.
  """
  def link_existing_user(token, current_user, attrs \\ %{}) do
    invite = get_invite_by_token(token)

    cond do
      is_nil(invite) ->
        {:error, :invite_not_found}

      not FamilyInvite.valid?(invite) ->
        {:error, :invite_expired_or_used}

      not emails_match?(current_user.email, invite.email) ->
        {:error, :email_mismatch}

      Ysc.Accounts.sub_account?(current_user) ->
        {:error, :already_linked_to_family}

      current_user.id == invite.primary_user_id ->
        {:error, :cannot_link_self}

      true ->
        case link_date_of_birth_changes(current_user, invite, attrs) do
          {:ok, dob_changes} ->
            do_link_existing_user(invite, current_user, dob_changes)

          {:error, _reason} = error ->
            error
        end
    end
  end

  defp link_date_of_birth_changes(current_user, invite, attrs) do
    cond do
      not child_invite?(invite) ->
        {:ok, %{}}

      adult?(current_user.date_of_birth) ->
        {:error, :child_is_adult}

      not date_of_birth_required_to_link?(current_user, invite) ->
        {:ok, %{}}

      blank_date_of_birth?(attrs) ->
        {:error, :date_of_birth_required}

      true ->
        changeset = link_date_of_birth_changeset(current_user, invite, attrs)

        if changeset.valid? do
          {:ok,
           %{
             date_of_birth: Ecto.Changeset.get_field(changeset, :date_of_birth)
           }}
        else
          {:error, Map.put(changeset, :action, :validate)}
        end
    end
  end

  defp blank_date_of_birth?(attrs) do
    (attrs["date_of_birth"] || attrs[:date_of_birth]) in [nil, ""]
  end

  defp do_link_existing_user(invite, current_user, dob_changes) do
    Repo.transaction(fn ->
      relationship = invite.relationship || :child
      primary_user_id = invite.primary_user_id

      case validate_invite_acceptance(Repo, invite) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      updated_user =
        current_user
        |> Ecto.Changeset.change(
          Map.merge(dob_changes, %{
            primary_user_id: primary_user_id,
            family_relationship: relationship
          })
        )
        |> Repo.update!()

      invite
      |> FamilyInvite.accept_changeset()
      |> Repo.update!()

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

      schedule_invite_accepted_email!(invite, updated_user)

      updated_user
    end)
    |> case do
      {:ok, updated_user} = ok ->
        Ysc.Accounts.MembershipCache.invalidate_user(updated_user.id)

        invalidate_family_link_profile_caches(
          updated_user.id,
          invite.primary_user_id
        )

        sync_board_volunteer_billing_after_family_change(
          invite.primary_user_id,
          updated_user.id
        )

        ok

      error ->
        error
    end
  end

  defp invalidate_family_link_profile_caches(user_id, primary_user_id) do
    UserProfileCache.invalidate_user(user_id)
    UserProfileCache.invalidate_user(primary_user_id)
  end

  defp sync_board_volunteer_billing_after_family_change(
         primary_user_id,
         affected_user_id
       ) do
    with %User{} = primary <- Ysc.Accounts.get_user(primary_user_id),
         %User{} = affected_user <- Ysc.Accounts.get_user(affected_user_id) do
      BoardVolunteerBilling.sync_after_family_membership_change(
        primary,
        affected_user
      )
    else
      _ -> :ok
    end
  end

  @doc """
  Sends an email to the member who sent the invite when it is accepted.
  """
  def notify_invite_accepted(%FamilyInvite{} = invite, %User{} = accepted_user) do
    attrs = invite_accepted_email_attrs(invite, accepted_user)

    Notifier.schedule_email(
      attrs.recipient,
      attrs.idempotency_key,
      attrs.subject,
      attrs.template,
      attrs.variables,
      attrs.text_body,
      attrs.user_id
    )
  end

  defp schedule_invite_accepted_email!(invite, accepted_user) do
    case notify_invite_accepted(invite, accepted_user) do
      %Oban.Job{} ->
        :ok

      {:error, reason} ->
        Repo.rollback({:invite_accepted_email_enqueue_failed, reason})
    end
  end

  defp invite_accepted_email_attrs(
         %FamilyInvite{} = invite,
         %User{} = accepted_user
       ) do
    inviter = invite_created_by_user(invite)
    inviter_first_name = inviter.first_name || "there"
    invitee_name = format_invitee_name(accepted_user)
    invitee_email = accepted_user.email || invite.email
    relationship_label = relationship_label(invite.relationship)

    family_management_url =
      YscWeb.Emails.Helpers.absolute_url("/users/settings/family")

    email_vars = %{
      inviter_first_name: inviter_first_name,
      invitee_name: invitee_name,
      invitee_email: invitee_email,
      relationship_label: relationship_label,
      family_management_url: family_management_url
    }

    subject =
      if invitee_name do
        "#{invitee_name} Accepted Your Family Invitation - YSC"
      else
        "Family Invitation Accepted - YSC"
      end

    invitee_display =
      if invitee_name,
        do: "#{invitee_name} (#{invitee_email})",
        else: invitee_email

    idempotency_key = "family_invite_accepted_#{invite.id}"

    %{
      recipient: inviter.email,
      idempotency_key: idempotency_key,
      subject: subject,
      template: "family_invite_accepted",
      variables: email_vars,
      text_body: """
      ==============================

      Hi #{inviter_first_name},

      Great news! #{invitee_display} has accepted your family membership invitation and joined your family account as your #{relationship_label}.

      They now have access to all membership benefits, including cabin bookings and member event tickets.

      Manage your family members: #{family_management_url}

      ==============================
      """,
      user_id: inviter.id
    }
  end

  defp format_invitee_name(%User{first_name: first_name, last_name: last_name})
       when is_binary(first_name) and first_name != "" do
    if is_binary(last_name) and last_name != "" do
      "#{first_name} #{last_name}"
    else
      first_name
    end
  end

  defp format_invitee_name(_), do: nil

  defp relationship_label(:spouse), do: "spouse"
  defp relationship_label("spouse"), do: "spouse"
  defp relationship_label(_), do: "child"

  defp emails_match?(user_email, invite_email)
       when is_binary(user_email) and is_binary(invite_email) do
    Email.normalize(user_email) == Email.normalize(invite_email)
  end

  defp emails_match?(_, _), do: false

  defp invite_email_matches_attrs?(%FamilyInvite{} = invite, user_attrs)
       when is_map(user_attrs) do
    submitted_email =
      Map.get(user_attrs, "email") || Map.get(user_attrs, :email)

    is_binary(submitted_email) and
      emails_match?(submitted_email, invite.email)
  end

  defp invite_email_matches_attrs?(_, _), do: false

  @doc """
  Lists all invites for a primary user (pending and accepted).

  The family-management and admin family tabs only render invite email,
  relationship, and expiry — they never show who created the row.
  """
  def list_invites(primary_user) do
    primary_user.id
    |> list_invites_query()
    |> Repo.all()
  end

  @doc """
  Lists all pending, valid invites for the given email address.

  Used to surface invitations on the recipient's membership page so they
  can accept without needing the original email link.
  """
  def list_pending_invites_for_email(email) when is_binary(email) do
    email
    |> list_pending_invites_for_email_query(DateTime.utc_now())
    |> Repo.all()
  end

  @doc """
  Revokes a pending invite.

  Only the primary user who created the invite can revoke it.
  Sends a cancellation email to the invitee before deleting the invite.
  """
  @dialyzer {:nowarn_function, revoke_invite: 2}
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
        primary_user = ensure_primary_user_loaded(primary_user)

        Multi.new()
        |> Multi.delete(:invite, invite)
        |> Notifier.schedule_email_multi(
          :invite_cancellation_email,
          invite_cancellation_email_attrs(invite, primary_user)
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{invite: deleted_invite}} -> {:ok, deleted_invite}
          {:error, :invite, changeset, _changes} -> {:error, changeset}
          {:error, _operation, reason, _changes} -> {:error, reason}
        end
    end
  end

  defp invite_cancellation_email_attrs(invite, primary_user) do
    email_vars = %{
      primary_user_name: primary_user.first_name,
      invite_email: invite.email
    }

    idempotency_key = "family_invite_cancelled_#{invite.id}"

    membership_email = Ysc.EmailConfig.membership_email()

    %{
      recipient: invite.email,
      idempotency_key: idempotency_key,
      subject: YscWeb.Emails.FamilyInviteCancelled.get_subject(),
      template: "family_invite_cancelled",
      variables: email_vars,
      text_body: """
      ==============================

      Hi there,

      Your family membership invitation from #{primary_user.first_name} has been cancelled.

      The invitation we sent to #{invite.email} no longer works. You cannot use that link to join this family membership.

      If you have questions, contact the person who invited you or email us at #{membership_email}.

      ==============================
      """,
      user_id: primary_user.id
    }
  end

  defp ensure_primary_user_loaded(primary_user) do
    if is_nil(primary_user.first_name) do
      Repo.get!(User, primary_user.id)
    else
      primary_user
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

      # Finding 83: family sub-accounts must never mint invites. Eligibility
      # previously only checked lifetime/family on *this* user, so a lifetime
      # member (or someone with their own family plan) who later joined another
      # household could invite a nested tree. Accept walked
      # has_active_membership?/1 up to the real primary and counted the 10-seat
      # cap against the nested id, bypassing the household limit.
      Ysc.Accounts.sub_account?(user) ->
        {:error, :not_primary_user}

      not has_family_or_lifetime_membership?(user) ->
        {:error, :invalid_membership_type}

      reserved_sub_account_slots(user) >= @max_sub_accounts ->
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
    count_sub_accounts_by_primary_id(primary_user.id)
  end

  defp count_sub_accounts_by_primary_id(primary_user_id) do
    from(u in User, where: u.primary_user_id == ^primary_user_id)
    |> Repo.aggregate(:count, :id)
  end

  defp reserved_sub_account_slots(primary_user) do
    count_sub_accounts(primary_user) + count_pending_child_invites(primary_user)
  end

  defp count_pending_child_invites(primary_user) do
    from(i in FamilyInvite,
      where: i.primary_user_id == ^primary_user.id,
      where: is_nil(i.accepted_at),
      where: i.expires_at > ^DateTime.utc_now(),
      where: i.relationship != :spouse and i.relationship != "spouse"
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_spouses(primary_user) do
    from(u in User,
      where:
        u.primary_user_id == ^primary_user.id and
          u.family_relationship == "spouse"
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_pending_spouse_invites(primary_user) do
    from(i in FamilyInvite,
      where:
        i.primary_user_id == ^primary_user.id and
          is_nil(i.accepted_at) and
          i.expires_at > ^DateTime.utc_now() and
          (i.relationship == "spouse" or i.relationship == :spouse)
    )
    |> Repo.aggregate(:count, :id)
  end

  defp validate_relationship_limits(primary_user, relationship) do
    cond do
      relationship == :spouse || relationship == "spouse" ->
        spouses =
          count_spouses(primary_user) +
            count_pending_spouse_invites(primary_user)

        if spouses >= @max_spouses do
          {:error, :max_spouses_reached}
        else
          :ok
        end

      reserved_sub_account_slots(primary_user) >= @max_sub_accounts ->
        {:error, :max_sub_accounts_reached}

      true ->
        :ok
    end
  end

  defp validate_child_not_adult(relationship, %FamilyMember{
         birth_date: birth_date
       }) do
    if child_relationship?(relationship) and adult?(birth_date) do
      {:error, :child_is_adult}
    else
      :ok
    end
  end

  defp validate_child_not_adult(_relationship, _family_member), do: :ok

  defp validate_email_not_registered(email, primary_user_id) do
    normalized = Email.normalize(email)

    case Ysc.Accounts.get_user_by_email(normalized) do
      nil -> :ok
      %{id: ^primary_user_id} -> :ok
      _other -> {:error, :email_already_registered}
    end
  end

  defp validate_no_pending_invite(email, primary_user_id) do
    normalized = Email.normalize(email)

    pending_invite =
      from(i in FamilyInvite,
        where: i.email == ^normalized,
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

  defp invite_email_attrs(invite, primary_user, family_member) do
    family_member_name =
      case family_member do
        %FamilyMember{first_name: first_name, last_name: last_name}
        when is_binary(first_name) ->
          format_family_member_name(first_name, last_name)

        _ ->
          nil
      end

    invite_url =
      YscWeb.Emails.Helpers.absolute_url(
        "/family-invite/#{invite.token}/accept"
      )

    idempotency_key = "family_invite_#{invite.id}"

    # Button text depends on whether invitee has an existing account
    existing_user = Ysc.Accounts.get_user_by_email(invite.email)

    invite_button_text =
      if existing_user do
        "Join family membership"
      else
        "Create account and join membership"
      end

    # Include family member name in email variables if available
    email_vars = %{
      primary_user_name: primary_user.first_name,
      invite_url: invite_url,
      expires_in_days: 30,
      family_member_name: family_member_name,
      invite_button_text: invite_button_text
    }

    %{
      recipient: invite.email,
      idempotency_key: idempotency_key,
      subject:
        "You're Invited to Join #{primary_user.first_name}'s Family Membership - YSC",
      template: "family_invite",
      variables: email_vars,
      text_body: """
      ==============================

      Hi#{if family_member_name, do: " #{family_member_name}", else: " there"},

      #{primary_user.first_name} has invited you to join their YSC family membership!

      Click the link below to create your account and start enjoying all the benefits:

      #{invite_url}

      This invite will expire in 30 days.

      ==============================
      """,
      user_id: primary_user.id
    }
  end

  defp get_family_member(_primary_user, family_member_id)
       when family_member_id in [nil, ""],
       do: nil

  # Always read from the DB: callers may hold a stale `family_members` preload
  # (e.g. onboarding upserts the member right before inviting).
  defp get_family_member(primary_user, family_member_id) do
    case Ecto.ULID.cast(family_member_id) do
      {:ok, id} -> Repo.get_by(FamilyMember, id: id, user_id: primary_user.id)
      :error -> nil
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
    case Repo.get_by(Address, user_id: primary_user_id) do
      %Address{} = primary_address ->
        existing_address = Repo.get_by(Address, user_id: sub_account.id)

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
        {:ok, nil}
    end
  end

  defp copy_most_connected_country_from_primary(sub_account, primary_user) do
    country =
      case primary_user do
        %User{most_connected_country: country} -> country
        _ -> nil
      end

    if not is_nil(country) and is_nil(sub_account.most_connected_country) do
      sub_account
      |> Ecto.Changeset.change(most_connected_country: country)
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

    case Address.changeset(%Address{}, address_attrs)
         |> Repo.insert() do
      {:ok, address} ->
        {:ok, address}

      {:error, changeset} ->
        require Ysc.Logging

        Ysc.Logging.warning("Failed to copy billing address for sub-account",
          user_id: sub_account.id,
          primary_user_id: primary_user_id,
          errors: inspect(changeset.errors)
        )

        {:ok, nil}
    end
  end

  defp invite_user_query do
    from(u in User, select: struct(u, ^@invite_user_fields))
  end

  defp get_invite_by_token_query(token) do
    primary_user_query = invite_user_query()
    created_by_user_query = invite_user_query()

    from(i in FamilyInvite,
      where: i.token == ^token,
      preload: [
        primary_user: ^primary_user_query,
        created_by_user: ^created_by_user_query
      ]
    )
  end

  defp list_invites_query(primary_user_id) do
    from(i in FamilyInvite,
      where: i.primary_user_id == ^primary_user_id,
      order_by: [desc: i.inserted_at]
    )
  end

  defp list_pending_invites_for_email_query(email, now)
       when is_binary(email) do
    normalized_email = Email.normalize(email)
    primary_user_query = invite_user_query()

    from(i in FamilyInvite,
      where:
        i.email == ^normalized_email and
          is_nil(i.accepted_at) and
          i.expires_at > ^now,
      order_by: [desc: i.inserted_at],
      preload: [primary_user: ^primary_user_query]
    )
  end

  defp invite_created_by_user(%FamilyInvite{} = invite) do
    if Ecto.assoc_loaded?(invite.created_by_user) and invite.created_by_user do
      invite.created_by_user
    else
      from(u in User,
        where: u.id == ^invite.created_by_user_id,
        select: struct(u, ^@invite_user_fields)
      )
      |> Repo.one!()
    end
  end

  defp invite_created_by_user_query(created_by_user_id) do
    from(u in User,
      where: u.id == ^created_by_user_id,
      select: struct(u, ^@invite_user_fields)
    )
  end

  @doc false
  def ci_query_explain_query do
    list_pending_invites_for_email_query(
      Ysc.Ci.QueryExplain.Fixtures.email(),
      Ysc.Ci.QueryExplain.Fixtures.now()
    )
  end

  @doc false
  def ci_query_explain_get_invite_by_token_query do
    get_invite_by_token_query("ci-query-explain-invite-token")
  end

  @doc false
  def ci_query_explain_list_invites_query do
    list_invites_query(Ysc.Ci.QueryExplain.Fixtures.ulid())
  end

  @doc false
  def ci_query_explain_invite_created_by_user_query do
    invite_created_by_user_query(Ysc.Ci.QueryExplain.Fixtures.ulid())
  end
end
