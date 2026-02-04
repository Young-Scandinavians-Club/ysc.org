defmodule Ysc.VerificationCache do
  @moduledoc """
  A simple cache for storing verification codes (email/SMS) with expiration.

  Uses a GenServer to store codes in memory with automatic cleanup.
  Codes are stored as {user_id, code_type} => {code, expires_at} tuples.
  """

  use GenServer

  # Client API

  @doc """
  Starts the verification cache.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores a verification code for a user with the given type and expiration time.

  ## Parameters
  - user_id: The user ID (typically ULID string)
  - code_type: Atom like :email_verification, :sms_verification, etc.
  - code: The verification code string
  - expires_in_seconds: How long until the code expires (default: 600 = 10 minutes)
  """
  def store_code(user_id, code_type, code, expires_in_seconds \\ 600) do
    expires_at = DateTime.add(DateTime.utc_now(), expires_in_seconds, :second)
    GenServer.call(__MODULE__, {:store, user_id, code_type, code, expires_at})
  end

  @doc """
  Retrieves a verification code for a user if it exists and hasn't expired.

  Returns {:ok, code} if found and valid, {:error, :not_found} if not found,
  or {:error, :expired} if found but expired.
  """
  def get_code(user_id, code_type) do
    GenServer.call(__MODULE__, {:get, user_id, code_type})
  end

  @doc """
  Verifies a code for a user. If the code matches and is valid, removes it from cache.

  Returns {:ok, :verified} if successful, {:error, reason} otherwise.
  """
  def verify_code(user_id, code_type, provided_code) do
    GenServer.call(__MODULE__, {:verify, user_id, code_type, provided_code})
  end

  @doc """
  Removes a code from the cache (useful for cleanup after successful verification).
  """
  def remove_code(user_id, code_type) do
    GenServer.call(__MODULE__, {:remove, user_id, code_type})
  end

  @doc """
  Cleans up expired codes manually (called periodically by cleanup timer).
  """
  def cleanup_expired do
    GenServer.call(__MODULE__, :cleanup)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Schedule cleanup every 5 minutes
    schedule_cleanup()
    {:ok, %{codes: %{}, timers: %{}}}
  end

  @impl true
  def handle_call({:store, user_id, code_type, code, expires_at}, _from, state) do
    key = {user_id, code_type}
    codes = Map.put(state.codes, key, {code, expires_at})

    # Cancel existing timer for this key if any
    timers = cancel_timer(state.timers, key)

    # Schedule cleanup for this specific code
    timer_ref = schedule_individual_cleanup(expires_at)
    timers = Map.put(timers, key, timer_ref)

    {:reply, :ok, %{state | codes: codes, timers: timers}}
  end

  @impl true
  def handle_call({:get, user_id, code_type}, _from, state) do
    key = {user_id, code_type}

    case Map.get(state.codes, key) do
      {code, expires_at} ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          {:reply, {:ok, code}, state}
        else
          # Code expired, remove it
          {_removed, codes} = Map.pop(state.codes, key)
          timers = cancel_timer(state.timers, key)
          {:reply, {:error, :expired}, %{state | codes: codes, timers: timers}}
        end

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:verify, user_id, code_type, provided_code}, _from, state) do
    key = {user_id, code_type}

    case Map.get(state.codes, key) do
      {stored_code, expires_at} ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          if provided_code == stored_code do
            # Code matches, remove it and return success
            {_removed, codes} = Map.pop(state.codes, key)
            timers = cancel_timer(state.timers, key)
            {:reply, {:ok, :verified}, %{state | codes: codes, timers: timers}}
          else
            {:reply, {:error, :invalid_code}, state}
          end
        else
          # Code expired, remove it
          {_removed, codes} = Map.pop(state.codes, key)
          timers = cancel_timer(state.timers, key)
          {:reply, {:error, :expired}, %{state | codes: codes, timers: timers}}
        end

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:remove, user_id, code_type}, _from, state) do
    key = {user_id, code_type}
    {_removed, codes} = Map.pop(state.codes, key)
    timers = cancel_timer(state.timers, key)
    {:reply, :ok, %{state | codes: codes, timers: timers}}
  end

  @impl true
  def handle_call(:cleanup, _from, state) do
    {codes, timers} = cleanup_expired_codes(state.codes, state.timers)
    {:reply, :ok, %{state | codes: codes, timers: timers}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    {codes, timers} = cleanup_expired_codes(state.codes, state.timers)
    # Schedule next cleanup
    schedule_cleanup()
    {:noreply, %{state | codes: codes, timers: timers}}
  end

  @impl true
  def handle_info({:cleanup_individual, key}, state) do
    # Remove expired individual code
    {_removed, codes} = Map.pop(state.codes, key)
    {_timer_ref, timers} = Map.pop(state.timers, key)
    {:noreply, %{state | codes: codes, timers: timers}}
  end

  # Helper functions

  defp schedule_cleanup do
    # Clean up every 5 minutes
    Process.send_after(self(), :cleanup, 5 * 60 * 1000)
  end

  defp schedule_individual_cleanup(expires_at) do
    # Calculate milliseconds until expiration
    now = DateTime.utc_now()
    ms_until_expiry = DateTime.diff(expires_at, now, :millisecond)

    # Add some buffer to ensure cleanup happens after expiration
    # 1 second buffer
    buffer_ms = 1000
    delay_ms = max(ms_until_expiry + buffer_ms, 0)

    Process.send_after(self(), {:cleanup_individual, nil}, delay_ms)
  end

  defp cleanup_expired_codes(codes, timers) do
    now = DateTime.utc_now()

    {valid_codes, expired_keys} =
      Enum.split_with(codes, fn {_key, {_code, expires_at}} ->
        DateTime.compare(expires_at, now) == :gt
      end)

    expired_keys = Enum.map(expired_keys, fn {key, _value} -> key end)

    # Cancel timers for expired keys
    timers = Enum.reduce(expired_keys, timers, &cancel_timer(&2, &1))

    {Map.new(valid_codes), timers}
  end

  defp cancel_timer(timers, key) do
    case Map.get(timers, key) do
      nil ->
        timers

      timer_ref ->
        Process.cancel_timer(timer_ref)
        Map.delete(timers, key)
    end
  end
end
