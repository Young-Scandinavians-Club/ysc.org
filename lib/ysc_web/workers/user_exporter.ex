defmodule YscWeb.Workers.UserExporter do
  @moduledoc """
  Oban worker for exporting user data to CSV format.

  Handles asynchronous export of user information with customizable fields
  and filtering options.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :exports, max_attempts: 1

  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Accounts.User
  alias Ysc.Accounts
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription

  @stream_rows_count 100
  @export_ready_attempts 20
  @export_ready_sleep_ms 50

  @type export_opts :: [
          channel: String.t(),
          fields: [atom()],
          only_subscribed: boolean(),
          created_by_user_id: String.t()
        ]

  @doc """
  Builds a user CSV export on the local node.

  Broadcasts `user_export:progress` on `channel` while exporting.
  Returns the authenticated admin download path when the file is ready.
  """
  @spec run_export(export_opts()) :: {:ok, String.t()} | {:error, String.t()}
  def run_export(opts) when is_list(opts) do
    channel = Keyword.fetch!(opts, :channel)
    fields = normalize_fields(Keyword.fetch!(opts, :fields))
    only_subscribed = Keyword.fetch!(opts, :only_subscribed)
    created_by_user_id = Keyword.fetch!(opts, :created_by_user_id)

    Ysc.Logging.info(
      "UserExporter: Starting export with fields: #{inspect(fields)}, only_subscribed: #{only_subscribed}"
    )

    try do
      build_csv(fields, only_subscribed, created_by_user_id)
      output_path = await_csv(channel)

      with :ok <- ensure_export_file_ready!(output_path) do
        {:ok, export_download_path(output_path)}
      end
    rescue
      e ->
        Ysc.Logging.error("UserExporter: Error during export: #{inspect(e)}")
        Ysc.Logging.error(Exception.format(:error, e, __STACKTRACE__))
        {:error, "Export failed: #{Exception.message(e)}"}
    end
  end

  def perform(%_{
        args: %{
          "channel" => channel,
          "fields" => fields,
          "only_subscribed" => only_subscribed,
          "created_by_user_id" => created_by_user_id
        }
      }) do
    case run_export(
           channel: channel,
           fields: fields,
           only_subscribed: only_subscribed,
           created_by_user_id: created_by_user_id
         ) do
      {:ok, export_path} ->
        YscWeb.Endpoint.broadcast(channel, "user_export:complete", export_path)
        :ok

      {:error, message} ->
        YscWeb.Endpoint.broadcast(channel, "user_export:failed", message)
        {:error, message}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp build_csv(fields, only_subscribed, created_by_user_id) do
    job_pid = self()
    Ysc.Logging.info("UserExporter: Starting build_csv")

    # Check how many entries we have to write out
    # helps us report back progress to parent caller
    Task.async(fn ->
      Ysc.Logging.info("UserExporter: Task started")
      # Build the base query (without preloads for counting)
      base_query = from(u in User)

      # Apply subscription filter if needed
      filtered_query =
        if only_subscribed do
          # Include users with:
          # 1. Active subscriptions (active, trialing, past_due) - their own or inherited
          # 2. Lifetime membership (lifetime_membership_awarded_at is not null) - their own or from primary user
          # 3. Sub-accounts whose primary user has active membership
          from(u in User,
            left_join: s in Subscription,
            on: s.user_id == u.id,
            left_join: pu in User,
            on: pu.id == u.primary_user_id,
            left_join: ps in Subscription,
            on: ps.user_id == pu.id,
            # User's own active subscription
            # User's own lifetime membership
            # Primary user's active subscription (inherited)
            # Primary user's lifetime membership (inherited)
            where:
              s.stripe_status in ["active", "trialing", "past_due"] or
                not is_nil(u.lifetime_membership_awarded_at) or
                ps.stripe_status in ["active", "trialing", "past_due"] or
                not is_nil(pu.lifetime_membership_awarded_at),
            distinct: true
          )
        else
          base_query
        end

      # Count without preloads (can't use preloads in subquery)
      total_count =
        Repo.one(from q in subquery(filtered_query), select: count(q.id))

      Ysc.Logging.info("UserExporter: Total count: #{total_count}")

      output_path = generate_output_path(created_by_user_id)
      Ysc.Logging.info("UserExporter: Output path: #{output_path}")
      file = File.open!(output_path, [:write, :utf8])

      # Stream in pages and preload each page in bulk. Per-row Repo.preload
      # here was an N+1 (billing address + subscriptions + primary user).
      Repo.transaction(fn ->
        filtered_query
        |> Repo.stream(max_rows: @stream_rows_count)
        |> Stream.chunk_every(@stream_rows_count)
        |> Stream.flat_map(&preload_users_for_export/1)
        |> Stream.with_index()
        |> Stream.map(fn {entry, index} ->
          build_csv_row(entry, index, fields, job_pid, total_count)
        end)
        |> CSV.encode(headers: true)
        |> Enum.each(&IO.write(file, &1))
      end)

      File.close(file)
      Ysc.Logging.info("UserExporter: File written and closed")

      send(job_pid, {:complete, output_path})

      output_path
    end)
  end

  defp preload_users_for_export(users) do
    users =
      Repo.preload(users, [
        :billing_address,
        :primary_user,
        subscriptions: [:subscription_items]
      ])

    primary_users =
      users
      |> Enum.map(& &1.primary_user)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.id)

    primary_by_id =
      if primary_users == [] do
        %{}
      else
        primary_users
        |> Repo.preload(subscriptions: [:subscription_items])
        |> Map.new(&{&1.id, &1})
      end

    Enum.map(users, fn user ->
      case user.primary_user_id do
        nil ->
          user

        primary_id ->
          %{user | primary_user: Map.get(primary_by_id, primary_id)}
      end
    end)
  end

  defp build_csv_row(row, index, fields, pid, total_count) do
    # Only report progress at end of each page
    if rem(index, @stream_rows_count) == 0 do
      send(pid, {:progress, trunc(index / total_count * 100)})
    end

    # Get membership info for this user
    {membership_type, {renewal_date, renewal_time, renewal_tz}} =
      get_membership_info(row)

    # Build result with standard fields
    # Fields come in as atoms from AdminUsersLive
    result =
      Enum.reduce(fields, %{}, fn field, acc ->
        field_atom =
          case field do
            field when is_atom(field) -> field
            field when is_binary(field) -> String.to_existing_atom(field)
          end

        if field_atom == :address do
          billing = row.billing_address

          acc
          |> Map.put(:address, billing && billing.address)
          |> Map.put(:city, billing && billing.city)
          |> Map.put(:region, billing && billing.region)
          |> Map.put(:postal_code, billing && billing.postal_code)
          |> Map.put(:country, billing && billing.country)
        else
          value = Map.get(row, field_atom)
          Map.put(acc, field_atom, value)
        end
      end)

    # Add membership columns
    result
    |> Map.put(:membership_type, membership_type)
    |> Map.put(:membership_renewal_date, renewal_date)
    |> Map.put(:membership_renewal_time, renewal_time)
    |> Map.put(:membership_renewal_tz, renewal_tz)
    |> Map.put(
      :membership_inherited,
      get_membership_inherited_status(row, membership_type)
    )
    |> Map.put(:primary_user_email, get_primary_user_email(row))
    |> Map.put(:primary_user_id, get_primary_user_id(row))
  end

  defp get_membership_info(user) do
    # If user is a sub-account, check primary user's membership
    user_to_check =
      if Accounts.sub_account?(user) do
        # Use preloaded primary_user if available
        primary_user =
          cond do
            # Check if we preloaded it in the stream
            Map.has_key?(user, :primary_user) && not is_nil(user.primary_user) ->
              user.primary_user

            # Check if the association is loaded
            Ecto.assoc_loaded?(user.primary_user) &&
                not is_nil(user.primary_user) ->
              user.primary_user

            # Otherwise fetch it
            true ->
              Accounts.get_primary_user(user)
          end

        primary_user || user
      else
        user
      end

    # Check for lifetime membership first
    if Accounts.has_lifetime_membership?(user_to_check) do
      {"Lifetime", {"Never", nil, nil}}
    else
      # Use preloaded subscriptions if available, otherwise query
      subscriptions =
        case user_to_check.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            # Subscriptions not preloaded, fetch them
            Subscriptions.list_subscriptions(user_to_check)

          subscriptions when is_list(subscriptions) ->
            # Subscriptions already preloaded
            subscriptions

          _ ->
            []
        end

      # Find active subscription
      active_subscription =
        subscriptions
        |> Enum.find(&Subscriptions.active?/1)

      case active_subscription do
        nil ->
          {nil, {nil, nil, nil}}

        subscription ->
          # Ensure subscription items are loaded
          subscription =
            if Ecto.assoc_loaded?(subscription.subscription_items) do
              subscription
            else
              Repo.preload(subscription, :subscription_items)
            end

          membership_type = get_membership_type_from_subscription(subscription)
          renewal_date = format_renewal_date(subscription.current_period_end)

          {membership_type, renewal_date}
      end
    end
  end

  defp get_membership_type_from_subscription(subscription) do
    plan_id = YscWeb.UserAuth.get_membership_plan_type(subscription)

    if plan_id do
      membership_plans = Application.get_env(:ysc, :membership_plans, [])

      case Enum.find(membership_plans, &(&1.id == plan_id)) do
        %{name: name} -> name
        _ -> "Unknown"
      end
    else
      nil
    end
  end

  defp format_renewal_date(nil), do: {nil, nil, nil}

  defp format_renewal_date(%DateTime{} = datetime) do
    local = DateTime.shift_zone!(datetime, "America/Los_Angeles")
    date = Timex.format!(local, "%Y-%m-%d", :strftime)
    time = Timex.format!(local, "%I:%M %p", :strftime)
    tz = local.zone_abbr
    {date, time, tz}
  end

  defp get_membership_inherited_status(user, membership_type) do
    # Check if user is a sub-account and has inherited membership
    if Accounts.sub_account?(user) do
      # If they have membership, it's inherited from primary user
      if membership_type != nil, do: "Yes", else: "No"
    else
      "No"
    end
  end

  defp get_primary_user_email(user) do
    # Get primary user email if user is a sub-account
    if Accounts.sub_account?(user) do
      primary_user = get_primary_user(user)

      if primary_user do
        primary_user.email
      else
        nil
      end
    else
      nil
    end
  end

  defp get_primary_user_id(user) do
    # Get primary user ID if user is a sub-account
    if Accounts.sub_account?(user) do
      primary_user = get_primary_user(user)

      if primary_user do
        primary_user.id
      else
        nil
      end
    else
      nil
    end
  end

  defp get_primary_user(user) do
    cond do
      # Check if we preloaded it in the stream
      Map.has_key?(user, :primary_user) && not is_nil(user.primary_user) ->
        user.primary_user

      # Check if the association is loaded
      Ecto.assoc_loaded?(user.primary_user) && not is_nil(user.primary_user) ->
        user.primary_user

      # Otherwise fetch it
      true ->
        Accounts.get_primary_user(user)
    end
  end

  defp await_csv(channel) do
    receive do
      {:progress, percent} ->
        Ysc.Logging.info(
          "Broadcasting to `user_export:progress` with value #{percent}"
        )

        YscWeb.Endpoint.broadcast(channel, "user_export:progress", percent)
        await_csv(channel)

      {:complete, export_path} ->
        Ysc.Logging.info("UserExporter: CSV build complete at #{export_path}")
        export_path
    after
      30_000 ->
        raise RuntimeError, "No progress after 30s. Giving up."
    end
  end

  defp normalize_fields(fields) do
    Enum.map(fields, fn
      field when is_atom(field) -> field
      field when is_binary(field) -> String.to_existing_atom(field)
    end)
  end

  defp export_download_path(output_path) do
    "/admin/exports/#{Path.basename(output_path)}"
  end

  defp ensure_export_file_ready!(
         output_path,
         attempts \\ @export_ready_attempts
       )

  defp ensure_export_file_ready!(_output_path, 0) do
    {:error, "Export file is not available yet. Please try again."}
  end

  defp ensure_export_file_ready!(output_path, attempts) do
    if File.regular?(output_path) do
      :ok
    else
      Process.sleep(@export_ready_sleep_ms)
      ensure_export_file_ready!(output_path, attempts - 1)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp generate_output_path(created_by_user_id) do
    ulid = Ecto.ULID.generate()
    time_now = Timex.now()
    formatted_now = Timex.format!(time_now, "%F", :strftime)
    export_directory = "#{:code.priv_dir(:ysc)}/static/exports"
    File.mkdir_p(export_directory)

    "#{export_directory}/ysc-user-export-#{formatted_now}-#{created_by_user_id}-#{ulid}.csv"
  end
end
