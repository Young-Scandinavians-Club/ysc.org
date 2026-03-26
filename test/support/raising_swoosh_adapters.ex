defmodule Ysc.Test.SwooshAdapterRaisesConstraintError do
  @moduledoc false
  use Swoosh.Adapter

  alias Ysc.Messages.MessageIdempotency

  @impl Swoosh.Adapter
  def deliver(_email, _config) do
    cs =
      MessageIdempotency.changeset(%MessageIdempotency{}, %{
        message_type: :email,
        idempotency_key: "constraint_test",
        message_template: "booking_confirmation"
      })

    raise Ecto.ConstraintError.exception(
            type: constraint_type(),
            constraint: constraint_name(),
            changeset: cs,
            action: :insert
          )
  end

  @impl Swoosh.Adapter
  def deliver_many(emails, config) do
    case emails do
      [first | _] -> deliver(first, config)
      [] -> :ok
    end
  end

  defp constraint_name do
    Application.get_env(:ysc, :test_constraint_error_name) ||
      "message_idempotency_entries_unique_index"
  end

  defp constraint_type do
    Application.get_env(:ysc, :test_constraint_error_type) || :unique
  end
end

defmodule Ysc.Test.SwooshAdapterRaisesRuntimeError do
  @moduledoc false
  use Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(_email, _config),
    do: raise(RuntimeError, "test mailer runtime failure")

  @impl Swoosh.Adapter
  def deliver_many([first | _], config), do: deliver(first, config)
  def deliver_many([], _config), do: :ok
end
