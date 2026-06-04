defmodule Ysc.Accounts.UserProfileCache do
  @moduledoc """
  Cache for user profile loads used in LiveView assigns (not session tokens).
  """

  @cache_name :ysc_cache
  @cache_prefix "user_profile:"
  @default_ttl 5 * 60 * 1000

  def get_user!(user_id, preloads \\ []) when is_binary(user_id) do
    if Ysc.ProcessCache.enabled?() do
      do_get_user!(user_id, preloads)
    else
      Ysc.Accounts.get_user_from_db!(user_id, preloads)
    end
  end

  defp do_get_user!(user_id, preloads) do
    preloads_key = preloads |> List.wrap() |> Enum.sort() |> :erlang.phash2()
    cache_key = "#{@cache_prefix}#{user_id}:#{preloads_key}"

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        user = Ysc.Accounts.get_user_from_db!(user_id, preloads)
        cache_with_ttl(cache_key, user)
        user

      {:ok, {:ttl_expires_at, ttl_expires_at, user}} ->
        now = System.system_time(:millisecond)

        if now < ttl_expires_at do
          user
        else
          refetch(cache_key, user_id, preloads)
        end

      {:ok, user} ->
        cache_with_ttl(cache_key, user)
        user

      {:error, _reason} ->
        Ysc.Accounts.get_user_from_db!(user_id, preloads)
    end
  end

  def invalidate_user(user_id) when is_binary(user_id) do
    case Cachex.keys(@cache_name) do
      {:ok, keys} ->
        prefix = "#{@cache_prefix}#{user_id}:"

        keys
        |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, prefix)))
        |> Enum.each(&Cachex.del(@cache_name, &1))

      _ ->
        :ok
    end

    :ok
  end

  defp refetch(cache_key, user_id, preloads) do
    Cachex.del(@cache_name, cache_key)
    user = Ysc.Accounts.get_user_from_db!(user_id, preloads)
    cache_with_ttl(cache_key, user)
    user
  end

  defp cache_with_ttl(key, value) do
    ttl_ms = Application.get_env(:ysc, :user_profile_cache_ttl_ms, @default_ttl)
    now = System.system_time(:millisecond)
    ttl_expires_at = now + ttl_ms

    Cachex.put(@cache_name, key, {:ttl_expires_at, ttl_expires_at, value},
      expire: ttl_ms
    )

    value
  end
end
