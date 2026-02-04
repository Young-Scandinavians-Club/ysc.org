defmodule Ysc.Settings do
  @moduledoc """
  Context module for managing site settings.

  Provides functions for retrieving and caching application-wide site settings.
  """
  require Logger
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.SiteSettings.SiteSetting

  # Cache all settings on app startup
  @settings_cache_key "all-site-settings"

  def start_link do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    # Warm up cache on startup
    cache_all_settings()
    {:ok, state}
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
    current_setting = Repo.get_by!(SiteSetting, name: name)

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
                Logger.debug(
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
                Logger.error("[Settings] Failed to create setting",
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
              Logger.debug(
                "[Settings] Database constraint violation, fetching existing setting",
                name: name,
                error: error_message
              )

              case Repo.get_by(SiteSetting, name: name) do
                nil ->
                  # Still not found, return default
                  Logger.warning(
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
              Logger.error("[Settings] Exception while creating setting",
                name: name,
                error: error_message,
                stacktrace: Exception.format_stacktrace(__STACKTRACE__)
              )

              default_value
            end
        end

      setting ->
        # Setting exists, return its value
        setting.value
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
  Ensures that all default site settings exist in the database.
  Useful for tests and initial setup.

  Note: This function does NOT update the cache. If you need the cache
  to be updated, call cache_all_settings() after this function.
  """
  def ensure_settings_exist do
    default_settings = [
      %{group: "general", name: "site_name", value: "YSC"},
      %{group: "general", name: "contact_email", value: "support@ysc.org"},
      %{
        group: "socials",
        name: "instagram",
        value: "https://www.instagram.com/theysc"
      },
      %{
        group: "socials",
        name: "facebook",
        value: "https://www.facebook.com/YoungScandinaviansClub/"
      },
      %{
        group: "socials",
        name: "discord",
        value: "https://discord.gg/dn2gdXRZbW"
      }
    ]

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

    # Don't update cache here - let the cache be lazy-loaded on first access
    # This prevents cache pollution in tests that clear the cache in their setup
    :ok
  end
end
