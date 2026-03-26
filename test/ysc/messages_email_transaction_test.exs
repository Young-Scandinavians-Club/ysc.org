defmodule Ysc.MessagesEmailTransactionTest do
  @moduledoc """
  Covers `Ysc.Messages` email paths when `Mailer.deliver/1` fails inside the
  idempotency transaction (`handle_email_transaction_error/4`).
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Swoosh.TestAssertions

  alias Ysc.Messages

  setup do
    prev = Application.get_env(:ysc, Ysc.Mailer) || []

    on_exit(fn ->
      Application.put_env(:ysc, Ysc.Mailer, prev)
    end)

    Application.put_env(
      :ysc,
      Ysc.Mailer,
      Keyword.merge(prev, adapter: Ysc.Test.FailingSwooshAdapter)
    )

    :ok
  end

  test "run_send_message_idempotent returns error when mailer fails in transaction" do
    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to("txn-fail@example.com")
      |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
      |> Swoosh.Email.subject("Txn fail")
      |> Swoosh.Email.html_body("<p>x</p>")

    key = "em_txn_fail_#{System.unique_integer()}"

    attrs = %{
      message_type: :email,
      idempotency_key: key,
      message_template: "booking_confirmation",
      params: %{},
      email: "txn-fail@example.com",
      rendered_message: "<p>x</p>"
    }

    assert {:error, "failed to send email"} =
             Messages.run_send_message_idempotent(email, attrs)

    assert_no_email_sent()

    assert Ysc.Repo.one(
             from(m in Ysc.Messages.MessageIdempotency,
               where: m.idempotency_key == ^key,
               select: count()
             )
           ) == 0
  end
end
