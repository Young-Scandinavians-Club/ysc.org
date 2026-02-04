defmodule YscWeb.Workers.KeilaSubscriber do
  @moduledoc """
  Oban worker for managing newsletter subscriptions in Keila.

  Processes newsletter subscriptions and unsubscriptions asynchronously to avoid blocking
  user registration or other operations.
  """
  require Logger
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ysc.Keila

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"email" => email, "action" => "subscribe"} = args
      }) do
    project_id = args["project_id"]
    form_id = args["form_id"]
    first_name = args["first_name"]
    last_name = args["last_name"]
    data = args["data"]

    Logger.info("KeilaSubscriber: Starting subscription",
      email: email,
      project_id: project_id,
      form_id: form_id,
      has_first_name: !is_nil(first_name),
      has_last_name: !is_nil(last_name),
      has_data: !is_nil(data)
    )

    opts = []
    opts = if project_id, do: [{:project_id, project_id} | opts], else: opts
    opts = if form_id, do: [{:form_id, form_id} | opts], else: opts
    opts = if first_name, do: [{:first_name, first_name} | opts], else: opts
    opts = if last_name, do: [{:last_name, last_name} | opts], else: opts
    opts = if data, do: [{:data, data} | opts], else: opts

    case Keila.subscribe_email(email, opts) do
      :ok ->
        Logger.info("KeilaSubscriber: Successfully subscribed", email: email)
        :ok

      {:error, :not_configured} ->
        Logger.debug("KeilaSubscriber: Keila not configured, skipping",
          email: email
        )

        :ok

      {:error, :invalid_email} ->
        Logger.warning("KeilaSubscriber: Invalid email address", email: email)
        {:error, "Invalid email address"}

      {:error, error} ->
        Logger.warning("KeilaSubscriber: Failed to subscribe",
          email: email,
          error: inspect(error)
        )

        {:error, "Failed to subscribe: #{inspect(error)}"}
    end
  end

  def perform(%Oban.Job{
        args: %{"email" => email, "action" => "unsubscribe"} = args
      }) do
    project_id = args["project_id"]

    Logger.info("KeilaSubscriber: Starting unsubscribe",
      email: email,
      project_id: project_id
    )

    opts = []
    opts = if project_id, do: [{:project_id, project_id} | opts], else: opts

    case Keila.unsubscribe_email(email, opts) do
      :ok ->
        Logger.info("KeilaSubscriber: Successfully unsubscribed", email: email)
        :ok

      {:error, :not_configured} ->
        Logger.debug("KeilaSubscriber: Keila not configured, skipping",
          email: email
        )

        :ok

      {:error, :invalid_email} ->
        Logger.warning("KeilaSubscriber: Invalid email address", email: email)
        {:error, "Invalid email address"}

      {:error, error} ->
        Logger.warning("KeilaSubscriber: Failed to unsubscribe",
          email: email,
          error: inspect(error)
        )

        {:error, "Failed to unsubscribe: #{inspect(error)}"}
    end
  end

  def perform(%Oban.Job{args: %{"email" => _email} = args}) do
    # Default to subscribe if no action is provided
    perform(%Oban.Job{args: Map.put(args, "action", "subscribe")})
  end

  def perform(%Oban.Job{args: args}) do
    Logger.warning("KeilaSubscriber: Invalid job args", args: args)
    {:error, "Invalid job args: email is required"}
  end
end
