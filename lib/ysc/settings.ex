defmodule Ysc.Settings do
  @moduledoc """
  Context module for managing site settings.

  Provides functions for retrieving and caching application-wide site settings.
  """
  use GenServer

  require Ysc.Logging
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.SiteSettings.SiteSetting

  # Cache all settings on app startup
  @settings_cache_key "all-site-settings"
  @site_setting_name_max_length 255

  @instagram_social_url "https://www.instagram.com/theysc"
  @facebook_social_url "https://www.facebook.com/YoungScandinaviansClub/"
  @partiful_social_url "https://partiful.com/u/nm9TVCDwC3y28CL4fcTX"
  @whatsapp_social_url "https://chat.whatsapp.com/LvsXNcpGPuH2pSTuGGaUwF?s=cl&p=i&ilr=1"

  @doc false
  def instagram_social_url, do: @instagram_social_url

  @doc false
  def facebook_social_url, do: @facebook_social_url

  @doc false
  def partiful_social_url, do: @partiful_social_url

  @doc false
  def whatsapp_social_url, do: @whatsapp_social_url

  @doc false
  def default_social_settings do
    [
      %{
        group: "socials",
        name: "instagram",
        value: @instagram_social_url
      },
      %{
        group: "socials",
        name: "facebook",
        value: @facebook_social_url
      },
      %{
        group: "socials",
        name: "partiful",
        value: @partiful_social_url
      },
      %{
        group: "socials",
        name: "whatsapp",
        value: @whatsapp_social_url
      }
    ]
  end

  @doc """
  Inserts default social site settings when missing.

  Used by dev/test/prod seed scripts so every environment gets the same social links.
  """
  def seed_default_social_settings(repo \\ Repo) do
    Enum.each(default_social_settings(), fn attrs ->
      changeset = SiteSetting.site_setting_changeset(%SiteSetting{}, attrs)

      case repo.insert(changeset,
             on_conflict: :nothing,
             conflict_target: [:name]
           ) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          Ysc.Logging.warning("Failed to seed social site setting",
            extra: %{name: attrs.name, errors: changeset.errors}
          )
      end
    end)

    maybe_warm_cache()
  end

  defp maybe_warm_cache do
    if Process.whereis(:ysc_cache), do: warm_cache()
  end

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    # Migration is complete — never leave webhook/email suppression enabled.
    ensure_wp_migration_inactive()
    # Warm up cache on startup
    cache_all_settings()
    {:ok, state}
  end

  @doc """
  Forces `wp_migration_active` to `"false"` when present.

  WordPress migration is done; this setting must stay off so Stripe webhook
  side effects (emails, QuickBooks, etc.) are not suppressed. Called on app
  boot and after WP load finishes.
  """
  def ensure_wp_migration_inactive do
    case Repo.get_by(SiteSetting, name: "wp_migration_active") do
      nil ->
        :ok

      %{value: value} when value != "true" ->
        :ok

      _setting ->
        case update_setting("wp_migration_active", "false") do
          {:ok, _} ->
            Ysc.Logging.info(
              "[Settings] Cleared wp_migration_active (migration complete)"
            )

            :ok

          {:error, reason} ->
            Ysc.Logging.error("Failed to clear wp_migration_active",
              error: reason
            )

            {:error, reason}
        end
    end
  end

  defp cache_all_settings do
    settings =
      Repo.all(
        from s in SiteSetting,
          order_by: [{:desc, :id}]
      )

    # Cache the full settings list
    Cachex.put(:ysc_cache, @settings_cache_key, settings)

    # Cache individual settings
    Enum.each(settings, fn setting ->
      Cachex.put(:ysc_cache, setting_cache_key(setting.name), setting.value)
    end)
  end

  def settings() do
    case Cachex.get(:ysc_cache, @settings_cache_key) do
      {:ok, nil} ->
        settings =
          Repo.all(
            from s in SiteSetting,
              order_by: [{:desc, :id}]
          )

        Cachex.put(:ysc_cache, @settings_cache_key, settings)
        settings

      {:ok, settings} ->
        settings

      _ ->
        Repo.all(
          from s in SiteSetting,
            order_by: [{:desc, :id}]
        )
    end
  end

  defp setting_cache_key(name) do
    "site-settings:#{name}"
  end

  def get_setting(name) do
    cache_key = setting_cache_key(name)

    case Cachex.get(:ysc_cache, cache_key) do
      {:ok, nil} ->
        setting_value = get_setting_value_from_db!(name)
        Cachex.put(:ysc_cache, cache_key, setting_value)
        setting_value

      {:ok, value} ->
        value

      _ ->
        get_setting_value_from_db!(name)
    end
  end

  defp get_setting_value_from_db!(name) do
    setting = Repo.get_by!(SiteSetting, name: name)
    setting.value
  end

  def update_setting(name, value) do
    case Repo.get_by(SiteSetting, name: name) do
      nil ->
        {:error, :not_found}

      current_setting ->
        update_setting!(current_setting, name, value)
    end
  end

  defp update_setting!(current_setting, name, value) do
    case SiteSetting.site_setting_changeset(current_setting, %{value: value})
         |> Repo.update() do
      {:ok, updated} ->
        # Update both caches
        Cachex.put(:ysc_cache, setting_cache_key(name), value)

        case Cachex.get(:ysc_cache, @settings_cache_key) do
          {:ok, settings} when is_list(settings) ->
            updated_settings =
              Enum.map(settings, fn setting ->
                if setting.name == name, do: updated, else: setting
              end)

            Cachex.put(:ysc_cache, @settings_cache_key, updated_settings)

          _ ->
            :ok
        end

        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Gets a setting value, or creates it with a default value if it doesn't exist.

  Returns the setting value (from DB or default).

  Handles race conditions where multiple processes try to create the same setting
  simultaneously by catching unique constraint violations and retrying with a fetch.
  """
  def get_or_create_setting(name, group, default_value \\ nil) do
    case Repo.get_by(SiteSetting, name: name) do
      nil ->
        # Avoid PostgreSQL varchar truncation errors (and noisy logs) for invalid names.
        if is_binary(name) and
             String.length(name) > @site_setting_name_max_length do
          default_value
        else
          do_get_or_create_setting_insert(name, group, default_value)
        end

      setting ->
        setting.value
    end
  end

  defp do_get_or_create_setting_insert(name, group, default_value) do
    # Setting doesn't exist, try to create it
    try do
      case Repo.insert(%SiteSetting{
             group: group,
             name: name,
             value: default_value
           }) do
        {:ok, setting} ->
          # Cache the new setting
          Cachex.put(:ysc_cache, setting_cache_key(name), setting.value)
          setting.value

        {:error, changeset} ->
          # Check if this is a unique constraint violation (race condition)
          # This can happen when multiple processes try to create the same setting simultaneously
          has_unique_error? =
            changeset.errors
            |> Enum.any?(fn
              {:name, {message, _}} when is_binary(message) ->
                String.contains?(message, "unique") or
                  String.contains?(message, "already exists") or
                  String.contains?(message, "duplicate")

              _ ->
                false
            end)

          if has_unique_error? do
            # Race condition: another process created the setting, fetch it
            Ysc.Logging.debug(
              "[Settings] Race condition detected, fetching existing setting",
              name: name
            )

            case Repo.get_by(SiteSetting, name: name) do
              nil ->
                # Still not found (unlikely), return default
                default_value

              setting ->
                # Found it, cache and return
                Cachex.put(
                  :ysc_cache,
                  setting_cache_key(name),
                  setting.value
                )

                setting.value
            end
          else
            # Some other error occurred
            Ysc.Logging.error("[Settings] Failed to create setting",
              name: name,
              errors: inspect(changeset.errors)
            )

            default_value
          end
      end
    rescue
      error ->
        # Handle database-level constraint violations or other exceptions
        # This might happen if the unique constraint is enforced at the DB level
        # and Ecto doesn't wrap it in a changeset error
        error_message = Exception.message(error)

        if String.contains?(error_message, "unique") or
             String.contains?(error_message, "duplicate") do
          # Likely a race condition, try fetching the existing setting
          Ysc.Logging.debug(
            "[Settings] Database constraint violation, fetching existing setting",
            name: name,
            error: error_message
          )

          case Repo.get_by(SiteSetting, name: name) do
            nil ->
              # Still not found, return default
              Ysc.Logging.warning(
                "[Settings] Setting not found after constraint violation",
                name: name
              )

              default_value

            setting ->
              # Found it, cache and return
              Cachex.put(:ysc_cache, setting_cache_key(name), setting.value)
              setting.value
          end
        else
          # Some other exception occurred
          Ysc.Logging.error("[Settings] Exception while creating setting",
            name: name,
            error: error_message,
            stacktrace: __STACKTRACE__
          )

          default_value
        end
    end
  end

  @doc """
  Gets a setting value safely (returns nil if not found instead of raising).
  """
  def get_setting_safe(name) do
    cache_key = setting_cache_key(name)

    case Cachex.get(:ysc_cache, cache_key) do
      {:ok, nil} ->
        case Repo.get_by(SiteSetting, name: name) do
          nil ->
            nil

          setting ->
            Cachex.put(:ysc_cache, cache_key, setting.value)
            setting.value
        end

      {:ok, value} ->
        value

      _ ->
        case Repo.get_by(SiteSetting, name: name) do
          nil -> nil
          setting -> setting.value
        end
    end
  end

  @doc """
  Returns a non-empty social/link setting URL, or `nil` if the setting is missing
  or only whitespace. Safer for templates than `get_setting/1`, which raises
  when the row is absent.
  """
  def get_social_url(name) do
    case get_setting_safe(name) do
      url when is_binary(url) ->
        case String.trim(url) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  def settings_grouped_by_scope() do
    settings()
    |> Enum.reduce(%{}, fn setting, acc ->
      # Convert nil group to "general", and ensure all keys are strings for Phoenix forms
      group = setting.group || "general"
      current = Map.get(acc, group, [])
      Map.put(acc, group, [setting | current])
    end)
  end

  def setting_scopes() do
    settings()
    |> Enum.map(fn setting -> setting.group || "general" end)
    |> Enum.uniq()
  end

  def clear_cache() do
    # Clear the main settings cache
    Cachex.del(:ysc_cache, @settings_cache_key)

    # Clear all individual setting caches
    # We need to clear all keys that match the pattern "site-settings:*"
    # Since Cachex doesn't support wildcard deletion, we use Cachex.keys/1 to get all keys
    # and then filter for setting keys
    case Cachex.keys(:ysc_cache) do
      {:ok, keys} ->
        keys
        |> Enum.filter(&String.starts_with?(to_string(&1), "site-settings:"))
        |> Enum.each(&Cachex.del(:ysc_cache, &1))

      _ ->
        :ok
    end
  end

  @doc """
  Reloads all site settings into Cachex. Used at application boot and in tests.
  """
  def warm_cache do
    cache_all_settings()
    :ok
  end

  @doc """
  Ensures that all default site settings exist in the database and warms the cache.
  Useful for tests and initial setup.
  """
  def ensure_settings_exist do
    default_settings =
      [
        %{group: "general", name: "site_name", value: "YSC"},
        %{group: "general", name: "contact_email", value: "support@ysc.org"}
      ] ++ default_social_settings()

    for setting <- default_settings do
      case Repo.get_by(SiteSetting, name: setting.name) do
        nil ->
          Repo.insert!(%SiteSetting{
            group: setting.group,
            name: setting.name,
            value: setting.value
          })

        _ ->
          :ok
      end
    end

    warm_cache()
  end

  @doc false
  def ci_query_explain_query do
    from(s in SiteSetting, order_by: [{:desc, :id}])
  end
end
