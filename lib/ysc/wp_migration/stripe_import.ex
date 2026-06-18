defmodule Ysc.WpMigration.StripeImport do
  @moduledoc """
  Stripe customer and subscription import during WordPress migration load.

  Links WP `cus_*` IDs, imports existing Stripe subscriptions before creating
  new ones, and accumulates failures into `stripe_import_failures.json`.
  """

  require Ysc.Logging
  import Ecto.Query
  alias Ysc.Repo
  alias Ysc.Accounts.User
  alias Ysc.Customers
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription
  alias Ysc.Stripe.RetryHelper
  alias Ysc.Stripe.SubscriptionHelpers

  @importable_statuses ~w(active trialing past_due unpaid paused)
  @report_filename "stripe_import_failures.json"

  @doc false
  def new_report do
    %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      failures: []
    }
  end

  @doc false
  def record_failure(report, attrs) when is_map(attrs) do
    entry =
      attrs
      |> Map.new()
      |> Map.put(
        :recorded_at,
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()
      )

    %{report | failures: [entry | report.failures]}
  end

  @doc false
  def failure_count(%{failures: failures}), do: length(failures)

  @doc false
  def write_report(report, export_dir) do
    payload = %{
      "generated_at" => DateTime.to_iso8601(report.generated_at),
      "failure_count" => failure_count(report),
      "failures" => Enum.reverse(report.failures)
    }

    content = Jason.encode!(payload, pretty: true)

    case Ysc.SafeFile.write_under_root(export_dir, @report_filename, content) do
      {:ok, path} ->
        path

      {:error, reason} ->
        raise "Unable to write #{@report_filename} under #{export_dir}: #{inspect(reason)}"
    end
  end

  @doc false
  def log_summary(report) do
    count = failure_count(report)

    if count == 0 do
      Ysc.Logging.info("[WP Load] Stripe import completed with no failures")
    else
      Ysc.Logging.warning(
        "[WP Load] Stripe import completed with #{count} failure(s) — see #{@report_filename}"
      )
    end
  end

  @doc false
  def link_wp_stripe_customer(%User{} = user, wp_cus_id, context, report)
      when is_binary(wp_cus_id) and wp_cus_id != "" do
    case retrieve_customer(wp_cus_id) do
      {:ok, _customer} ->
        case persist_stripe_id(user, wp_cus_id) do
          {:ok, updated_user} ->
            {:ok, updated_user, report}

          {:error, reason} ->
            report =
              record_failure(
                report,
                failure_attrs(context, "stripe_customer_persist", %{
                  stripe_customer_id: wp_cus_id,
                  reason: inspect(reason)
                })
              )

            {:error, reason, report}
        end

      {:error, :resource_missing} ->
        resolve_missing_wp_customer(user, context, report)

      {:error, reason} ->
        report =
          record_failure(
            report,
            failure_attrs(context, "stripe_customer_link", %{
              stripe_customer_id: wp_cus_id,
              reason: reason
            })
          )

        {:error, reason, report}
    end
  end

  def link_wp_stripe_customer(%User{} = user, _wp_cus_id, _context, report),
    do: {:ok, user, report}

  @doc false
  def ensure_stripe_customer_for_user(%User{} = user, context, report) do
    cond do
      is_nil(user.stripe_id) or user.stripe_id == "" ->
        create_fresh_stripe_customer(user, context, report)

      true ->
        case retrieve_customer(user.stripe_id) do
          {:ok, _customer} ->
            {:ok, user, report}

          {:error, :resource_missing} ->
            create_fresh_stripe_customer(user, context, report)

          {:error, reason} ->
            report =
              record_failure(
                report,
                failure_attrs(context, "stripe_customer_verify", %{
                  stripe_customer_id: user.stripe_id,
                  reason: reason
                })
              )

            {:error, reason, report}
        end
    end
  end

  @doc false
  def import_subscriptions_for_user(%User{} = user, context, report) do
    cond do
      is_nil(user.stripe_id) or user.stripe_id == "" ->
        {:ok, :no_stripe_customer, report}

      user_has_real_subscription?(user.id) ->
        remove_migrated_placeholder(user.id)
        {:ok, :already_linked, report}

      true ->
        case list_customer_subscriptions(user.stripe_id) do
          {:ok, subscriptions} ->
            importable = Enum.filter(subscriptions, &importable_subscription?/1)

            if importable == [] do
              {:ok, :none_found, report}
            else
              import_subscriptions(user, importable, context, report)
            end

          {:error, reason} ->
            report =
              record_failure(
                report,
                failure_attrs(context, "stripe_subscription_list", %{
                  stripe_customer_id: user.stripe_id,
                  reason: reason
                })
              )

            {:error, reason, report}
        end
    end
  end

  @doc false
  def customer_has_importable_stripe_subscription?(stripe_customer_id)
      when is_binary(stripe_customer_id) and stripe_customer_id != "" do
    case list_customer_subscriptions(stripe_customer_id) do
      {:ok, subscriptions} ->
        Enum.any?(subscriptions, &importable_subscription?/1)

      {:error, _} ->
        false
    end
  end

  def customer_has_importable_stripe_subscription?(_), do: false

  @doc false
  def importable_subscription?(%{status: status})
      when status in @importable_statuses,
      do: true

  def importable_subscription?(
        %{status: "canceled", cancel_at_period_end: true} = sub
      ),
      do: period_end_in_future?(sub)

  def importable_subscription?(_), do: false

  defp import_subscriptions(user, subscriptions, context, report) do
    {report, imported?} =
      Enum.reduce(subscriptions, {report, false}, fn stripe_sub,
                                                     {acc_report, imported} ->
        case Subscriptions.create_subscription_from_stripe(user, stripe_sub) do
          {:ok, _subscription} ->
            {acc_report, true}

          {:error, reason} ->
            report =
              record_failure(
                acc_report,
                failure_attrs(context, "stripe_subscription_import", %{
                  stripe_customer_id: user.stripe_id,
                  stripe_subscription_id: stripe_sub.id,
                  reason: inspect(reason)
                })
              )

            {report, imported}
        end
      end)

    if imported? do
      remove_migrated_placeholder(user.id)
      {:ok, :imported, report}
    else
      {:error, :import_failed, report}
    end
  end

  defp resolve_missing_wp_customer(%User{} = user, context, report) do
    if is_binary(user.stripe_id) and user.stripe_id != "" do
      case retrieve_customer(user.stripe_id) do
        {:ok, _customer} ->
          Ysc.Logging.info(
            "[WP Load] WP Stripe customer #{context[:wp_stripe_customer_id]} not found; " <>
              "keeping existing #{user.stripe_id} for user #{user.id}"
          )

          {:ok, user, report}

        {:error, :resource_missing} ->
          create_fresh_stripe_customer(user, context, report)

        {:error, reason} ->
          report =
            record_failure(
              report,
              failure_attrs(context, "stripe_customer_link", %{
                stripe_customer_id: context[:wp_stripe_customer_id],
                reason: reason
              })
            )

          {:error, reason, report}
      end
    else
      create_fresh_stripe_customer(user, context, report)
    end
  end

  defp create_fresh_stripe_customer(%User{} = user, context, report) do
    original_stripe_id = user.stripe_id

    case Customers.create_stripe_customer(Repo.get!(User, user.id)) do
      {:ok, _} ->
        fresh_user = Repo.get!(User, user.id)

        if fresh_user.stripe_id && fresh_user.stripe_id != original_stripe_id do
          {:ok, fresh_user, report}
        else
          reason =
            "Stripe customer API call succeeded but stripe_id was not persisted"

          report =
            record_failure(
              report,
              failure_attrs(context, "stripe_customer_create", %{
                stripe_customer_id: original_stripe_id,
                reason: reason
              })
            )

          {:error, :no_stripe_id, report}
        end

      {:error, reason} ->
        report =
          record_failure(
            report,
            failure_attrs(context, "stripe_customer_create", %{
              stripe_customer_id: original_stripe_id,
              reason: inspect(reason)
            })
          )

        {:error, reason, report}
    end
  end

  defp persist_stripe_id(%User{} = user, stripe_customer_id) do
    if user.stripe_id == stripe_customer_id do
      {:ok, user}
    else
      user
      |> User.update_user_changeset(%{stripe_id: stripe_customer_id})
      |> Repo.update()
    end
  end

  defp retrieve_customer(stripe_customer_id) do
    case RetryHelper.stripe_retry_transient(fn ->
           stripe_customer_module().retrieve(stripe_customer_id, [])
         end) do
      {:ok, customer} ->
        {:ok, customer}

      {:error, %Stripe.Error{code: :resource_missing}} ->
        {:error, :resource_missing}

      {:error, %Stripe.Error{code: code} = error}
      when code in [:not_found, :invalid_request_error] ->
        if get_http_status(error) == 404 do
          {:error, :resource_missing}
        else
          {:error, format_stripe_error(error)}
        end

      {:error, %Stripe.Error{} = error} ->
        {:error, format_stripe_error(error)}

      {:error, other} ->
        {:error, inspect(other)}
    end
  end

  defp list_customer_subscriptions(stripe_customer_id) do
    list_customer_subscriptions(stripe_customer_id, nil, [])
  end

  defp list_customer_subscriptions(stripe_customer_id, starting_after, acc) do
    params =
      %{customer: stripe_customer_id, status: "all", limit: 100}
      |> maybe_put_starting_after(starting_after)

    case RetryHelper.stripe_retry_transient(fn ->
           stripe_subscription_module().list(params)
         end) do
      {:ok, %{data: data, has_more: true}} when is_list(data) and data != [] ->
        last_id = List.last(data).id
        list_customer_subscriptions(stripe_customer_id, last_id, acc ++ data)

      {:ok, %{data: data}} when is_list(data) ->
        {:ok, acc ++ data}

      {:error, %Stripe.Error{} = error} ->
        {:error, format_stripe_error(error)}

      {:error, other} ->
        {:error, inspect(other)}
    end
  end

  defp maybe_put_starting_after(params, nil), do: params

  defp maybe_put_starting_after(params, id),
    do: Map.put(params, :starting_after, id)

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    user_has_real_subscription_query(Fixtures.ulid())
  end

  defp user_has_real_subscription?(user_id) do
    Repo.exists?(user_has_real_subscription_query(user_id))
  end

  defp user_has_real_subscription_query(user_id) do
    from(s in Subscription,
      where: s.user_id == ^user_id,
      where: not like(s.stripe_id, "migrated_%")
    )
  end

  @doc false
  def remove_migrated_placeholder(user_id) do
    migrated_id = "migrated_#{user_id}"

    case Subscriptions.get_subscription_by_stripe_id(migrated_id) do
      nil ->
        :ok

      subscription ->
        case Subscriptions.delete_subscription(subscription) do
          {:ok, _} ->
            Ysc.Logging.info(
              "[WP Load] Removed migrated placeholder subscription #{migrated_id}"
            )

            :ok

          {:error, reason} ->
            Ysc.Logging.warning(
              "[WP Load] Failed to remove migrated placeholder #{migrated_id}: #{inspect(reason)}"
            )

            :error
        end
    end
  end

  defp period_end_in_future?(%{} = sub) do
    case SubscriptionHelpers.current_period_end(sub) do
      nil ->
        false

      unix when is_integer(unix) ->
        DateTime.compare(DateTime.from_unix!(unix), DateTime.utc_now()) == :gt
    end
  end

  defp failure_attrs(context, category, extra) do
    %{
      category: category,
      user_id: context[:user_id],
      email: context[:email],
      wp_user_id: context[:wp_user_id],
      wp_stripe_customer_id: context[:wp_stripe_customer_id]
    }
    |> Map.merge(extra)
  end

  defp format_stripe_error(%Stripe.Error{} = error) do
    parts =
      [
        error.code && "code=#{error.code}",
        error.message && "message=#{error.message}",
        get_http_status(error) && "http_status=#{get_http_status(error)}"
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(parts, ", ")
  end

  defp get_http_status(%Stripe.Error{extra: %{http_status: status}})
       when is_integer(status),
       do: status

  defp get_http_status(%Stripe.Error{extra: %{"http_status" => status}})
       when is_integer(status),
       do: status

  defp get_http_status(_), do: nil

  defp stripe_customer_module do
    Application.get_env(:ysc, :stripe_customer_module, Stripe.Customer)
  end

  defp stripe_subscription_module do
    Application.get_env(:ysc, :stripe_subscription_module, Stripe.Subscription)
  end
end
