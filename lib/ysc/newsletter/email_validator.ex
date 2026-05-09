defmodule Ysc.Newsletter.EmailValidator do
  @moduledoc """
  Validates email addresses for newsletter signup to prevent spam.

  Performs two levels of validation:
  1. DNS MX record verification - ensures the domain can receive email
  2. Disposable domain blocking - prevents throwaway email addresses

  The validator is designed to fail open on temporary errors (e.g., DNS timeouts)
  to avoid blocking legitimate users due to infrastructure issues.
  """
  require Ysc.Logging

  @ets_table :disposable_email_domains
  @mx_cache_ttl :timer.minutes(10)

  @doc """
  Validates an email address for newsletter signup.

  Returns `:ok` if the email passes all checks, or `{:error, reason}` otherwise.

  Error reasons:
  - `:invalid_email` - malformed email address
  - `:no_mx_records` - domain cannot receive email (no MX records)
  - `:disposable_email` - throwaway/temporary email domain blocked

  ## Examples

      iex> validate_email("user@example.com")
      :ok

      iex> validate_email("user@mailinator.com")
      {:error, :disposable_email}

      iex> validate_email("user@nonexistentdomain123456.com")
      {:error, :no_mx_records}
  """
  def validate_email(email) when is_binary(email) do
    email = String.trim(email)

    with :ok <- validate_format(email),
         domain <- extract_domain(email),
         :ok <- check_disposable_domain(domain) do
      check_mx_records(domain)
    end
  end

  def validate_email(_), do: {:error, :invalid_email}

  @doc """
  Initializes the ETS table and loads disposable domains from file.

  Called by the application supervisor at startup.
  """
  def init_ets_table do
    # Create ETS table if it doesn't exist
    unless ets_table_exists?() do
      :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true])
    end

    load_disposable_domains()
  end

  @doc """
  Reloads the disposable domains list from disk into ETS.

  This can be called after updating the domains file via Mix task.
  """
  def reload_disposable_domains do
    load_disposable_domains()
  end

  # Private functions

  defp validate_format(email) do
    if String.contains?(email, "@") && String.length(email) > 3 do
      :ok
    else
      {:error, :invalid_email}
    end
  end

  defp extract_domain(email) do
    email
    |> String.split("@")
    |> List.last()
    |> String.downcase()
  end

  defp check_disposable_domain(domain) do
    if disposable_domain?(domain) do
      Ysc.Logging.info("Blocked disposable email domain",
        domain: domain,
        context: "newsletter_signup"
      )

      {:error, :disposable_email}
    else
      :ok
    end
  end

  defp disposable_domain?(domain) do
    case :ets.lookup(@ets_table, domain) do
      [{^domain, true}] -> true
      _ -> false
    end
  end

  defp check_mx_records(domain) do
    case get_cached_mx_result(domain) do
      {:ok, result} ->
        result

      :miss ->
        result = perform_mx_lookup(domain)
        cache_mx_result(domain, result)
        result
    end
  end

  defp perform_mx_lookup(domain) do
    charlist_domain = String.to_charlist(domain)

    # Set a reasonable timeout for DNS lookups (5 seconds)
    case :inet_res.lookup(charlist_domain, :in, :mx, timeout: 5000) do
      [] ->
        Ysc.Logging.info("No MX records found for domain",
          domain: domain,
          context: "newsletter_signup"
        )

        {:error, :no_mx_records}

      [_ | _] = _mx_records ->
        :ok
    end
  rescue
    e ->
      # On exception, fail open - don't block the user
      Ysc.Logging.warning("MX lookup exception, failing open",
        error: e,
        domain: domain,
        context: "newsletter_signup"
      )

      :ok
  end

  # Simple in-memory cache for MX lookups using process dictionary
  # This is per-LiveView process, so it's lightweight and automatic
  defp get_cached_mx_result(domain) do
    cache_key = {:mx_cache, domain}

    case Process.get(cache_key) do
      {result, expires_at} ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, result}
        else
          Process.delete(cache_key)
          :miss
        end

      nil ->
        :miss
    end
  end

  defp cache_mx_result(domain, result) do
    cache_key = {:mx_cache, domain}
    expires_at = System.monotonic_time(:millisecond) + @mx_cache_ttl
    Process.put(cache_key, {result, expires_at})
    :ok
  end

  defp load_disposable_domains do
    path = Application.app_dir(:ysc, "priv/disposable_domains.txt")

    case File.read(path) do
      {:ok, content} ->
        domains =
          content
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == "" || String.starts_with?(&1, "#")))

        # Clear existing entries (if reloading)
        :ets.delete_all_objects(@ets_table)

        # Insert all domains
        Enum.each(domains, fn domain ->
          :ets.insert(@ets_table, {String.downcase(domain), true})
        end)

        count = :ets.info(@ets_table, :size)

        Ysc.Logging.info("Loaded disposable email domains",
          count: count,
          source: path
        )

        {:ok, count}

      {:error, reason} ->
        Ysc.Logging.error("Failed to load disposable domains file",
          error: reason,
          path: path
        )

        {:error, reason}
    end
  end

  defp ets_table_exists? do
    case :ets.whereis(@ets_table) do
      :undefined -> false
      _ -> true
    end
  end
end
