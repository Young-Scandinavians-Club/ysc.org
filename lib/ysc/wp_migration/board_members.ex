defmodule Ysc.WpMigration.BoardMembers do
  @moduledoc """
  Canonical board-of-directors roster for the WP migration.

  Maps member emails to board positions so imports can attach the correct
  officer role after users are loaded. Gmail addresses are matched using
  `Ysc.Accounts.Email.normalize/1`, so dotted variants resolve to the
  same account.
  """

  require Ysc.Logging

  alias Ysc.Accounts
  alias Ysc.Accounts.{Email, User}
  alias Ysc.Repo

  @type member_config :: %{
          optional(:first_name) => String.t(),
          optional(:last_name) => String.t(),
          optional(:board_bio) => String.t(),
          required(:position) => atom()
        }

  @members [
    %{
      email: "admin@thenordstroms.net",
      position: :president,
      last_name: "Nordström"
    },
    %{
      email: "henrikflodell@gmail.com",
      position: :secretary,
      board_bio:
        "Henrik has been on the YSC webtech committee for several years, and joined the board as secretary following the 2024 AGM. He grew up in Sweden, studied computer science, lived on an island in the archipelago with future-president Jeanette, and moved with her to the Bay Area in 2009 for a career in semiconductor marketing."
    },
    %{
      email: "lauraflink92@gmail.com",
      position: :vice_president,
      first_name: "Laura",
      board_bio: "Vice President & Event Director"
    },
    %{
      email: "eaz.holm@gmail.com",
      position: :member_outreach
    },
    %{
      email: "backman93@gmail.com",
      position: :treasurer,
      board_bio:
        "While Johan calls Berkeley home he is originally from a few hours north of Stockholm in Sweden. After completing a MSc in Computer Science at Chalmers he has worked in several tech startups around the Bay Area and is now working in Financial Services Technology. He is now bringing his Swedish tech skills to the Board."
    },
    %{
      email: "daveconroy@me.com",
      position: :clear_lake_cabin_master,
      first_name: "Dave",
      last_name: "Conroy",
      board_bio: "Dave grew up as a poor boy in the slums of London."
    },
    %{
      email: "drlundbaek@gmail.com",
      position: :tahoe_cabin_master,
      board_bio:
        "Jesper Lundbaek was born into the YSC. His Father Borge and Mother Inger immigrated from Denmark in 1964 to the bay area. They immediately found a vibrant and active Scandinavian community of which they became a part of. Jesper was affectionately referred to as the \"1st child of Clear Lake\" since his parents and their friends were steady fixtures there in activities and the transformation to the property we enjoy today. As a board member for several years from the 90's into the 2000's, Jesper has had experience running the YSC, problem solving, and helping make decisions that benefit the club and its members. His latest activity with the club has been as the Tahoe Cabin Reservation Master since 2006."
    },
    %{
      email: "polina.pribytkova@gmail.com",
      position: :event_director
    },
    %{
      email: "elsaputur@gmail.com",
      position: :membership_director,
      board_bio: "Social Media & Marketing"
    },
    %{
      email: "acbuike@gmail.com",
      position: :event_director
    },
    %{
      email: "chrtev@gmail.com",
      position: :event_director
    }
  ]

  @doc """
  Returns the configured board roster (email keys are Gmail-normalized).
  """
  @spec members() :: [map()]
  def members, do: @members

  @doc """
  Applies board positions (and optional bios/names) to all configured members.

  Users must already exist except for manual-only entries (e.g. Dave Conroy),
  which are created as active members without passwords when missing.
  """
  @spec sync_all(keyword()) :: {:ok, map()}
  def sync_all(opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    only_emails = Keyword.get(opts, :only_emails)

    members =
      case only_emails do
        nil ->
          @members

        emails when is_list(emails) ->
          normalized = Email.normalize_set(emails)

          Enum.filter(@members, fn config ->
            Email.normalize(config.email) in normalized
          end)

        email when is_binary(email) ->
          sync_all(Keyword.put(opts, :only_emails, [email]))
      end

    results =
      Enum.map(members, fn config ->
        sync_member(config, dry_run)
      end)

    stats = %{
      assigned: Enum.count(results, &(&1.status == :assigned)),
      created: Enum.count(results, &(&1.status == :created)),
      skipped: Enum.count(results, &(&1.status == :skipped)),
      failed: Enum.count(results, &(&1.status == :failed)),
      results: results
    }

    {:ok, stats}
  end

  @doc """
  Applies the board position for a single user when their email is on the roster.
  """
  @spec sync_for_user(User.t()) :: :ok | :not_board_member
  def sync_for_user(%User{} = user) do
    case member_config_for_email(user.email) do
      nil ->
        :not_board_member

      config ->
        case sync_member(Map.put(config, :user, user), false) do
          %{status: status} when status in [:assigned, :created, :skipped] ->
            :ok

          %{status: :failed, reason: reason} ->
            raise "board sync failed for #{user.email}: #{inspect(reason)}"
        end
    end
  end

  defp sync_member(config, dry_run) do
    email = Email.normalize(config.email)

    case find_or_create_user(config, dry_run) do
      {:ok, %User{} = user, created?} ->
        if dry_run do
          %{email: email, status: :skipped, user_id: user.id, dry_run: true}
        else
          apply_board_config(user, config, created?)
        end

      {:error, reason} ->
        Ysc.Logging.warning(
          "[WP Board] Failed to sync #{email}: #{inspect(reason)}"
        )

        %{email: email, status: :failed, reason: reason}

      :skipped ->
        %{email: email, status: :skipped, dry_run: true}
    end
  end

  defp find_or_create_user(%{user: %User{} = user}, _dry_run),
    do: {:ok, user, false}

  defp find_or_create_user(config, true = _dry_run) do
    case Accounts.get_user_by_email(config.email) do
      %User{} = user ->
        {:ok, user, false}

      nil ->
        if manual_member?(config), do: :skipped, else: {:error, :user_not_found}
    end
  end

  defp find_or_create_user(config, false) do
    case Accounts.get_user_by_email(config.email) do
      %User{} = user ->
        {:ok, user, false}

      nil ->
        if manual_member?(config) do
          case create_manual_member(config) do
            {:ok, user} -> {:ok, user, true}
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, :user_not_found}
        end
    end
  end

  defp manual_member?(config) do
    Map.has_key?(config, :first_name) and Map.has_key?(config, :last_name) and
      config.email == "daveconroy@me.com"
  end

  defp create_manual_member(config) do
    attrs = %{
      "email" => Email.normalize(config.email),
      "first_name" => config.first_name,
      "last_name" => config.last_name,
      "state" => "active",
      "role" => "member"
    }

    %User{}
    |> User.registration_changeset(attrs,
      require_password: false,
      validate_email: false,
      hash_password: false
    )
    |> Ecto.Changeset.put_change(:state, :active)
    |> Repo.insert()
  end

  defp apply_board_config(%User{} = user, config, created?) do
    position = config.position

    with {:ok, %User{} = user} <- Accounts.assign_board_position(user, position),
         {:ok, %User{}} <- maybe_update_profile(user, config) do
      status = if created?, do: :created, else: :assigned

      %{email: user.email, status: status, user_id: user.id, position: position}
    else
      {:error, reason} ->
        %{email: user.email, status: :failed, reason: reason}
    end
  end

  defp maybe_update_profile(%User{} = user, config) do
    attrs =
      %{}
      |> maybe_put_attr(:first_name, Map.get(config, :first_name))
      |> maybe_put_attr(:last_name, Map.get(config, :last_name))
      |> maybe_put_attr(:board_bio, Map.get(config, :board_bio))

    if attrs == %{} do
      {:ok, user}
    else
      user
      |> User.update_user_changeset(attrs)
      |> Repo.update()
    end
  end

  defp maybe_put_attr(attrs, _key, nil), do: attrs
  defp maybe_put_attr(attrs, _key, ""), do: attrs
  defp maybe_put_attr(attrs, key, value), do: Map.put(attrs, key, value)

  defp member_config_for_email(email) when is_binary(email) do
    normalized = Email.normalize(email)

    Enum.find(@members, fn config ->
      Email.normalize(config.email) == normalized
    end)
  end
end
