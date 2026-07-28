defmodule YscWeb.Workers.EmailNotifierRenderFailureTest do
  use Ysc.DataCase, async: false

  import ExUnit.CaptureLog

  alias Ysc.Messages.MessageIdempotency
  alias YscWeb.Workers.EmailNotifier

  test "records a deferred rendering failure as terminal and logs diagnostics" do
    key = "render_failure_#{System.unique_integer([:positive])}"

    log =
      capture_log(fn ->
        assert {:error, :email_render_failed} =
                 perform_job(EmailNotifier, %{
                   "recipient" => "member@example.com",
                   "idempotency_key" => key,
                   "subject" => "New sign-in",
                   "template" => "new_sign_in_detected",
                   "params" => %{"auth_event_id" => Ecto.ULID.generate()},
                   "text_body" => "",
                   "user_id" => nil,
                   "category" => "account"
                 })
      end)

    assert log =~ "Email rendering failed; delivery marked terminal"

    assert %MessageIdempotency{delivery_status: :terminal_failed} =
             Ysc.Repo.get_by(MessageIdempotency, idempotency_key: key)
  end
end
