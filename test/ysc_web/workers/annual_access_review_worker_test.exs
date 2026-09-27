defmodule YscWeb.Workers.AnnualAccessReviewWorkerTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Workers.AnnualAccessReviewWorker
  alias YscWeb.Workers.EmailNotifier

  test "emails the WebTech team every admin and volunteer" do
    admin =
      user_fixture(%{
        role: :admin,
        board_position: :tahoe_cabin_master,
        first_name: "Astrid",
        last_name: "Lind"
      })

    volunteer = user_fixture(%{role: :volunteer})
    member = user_fixture(%{role: :member})

    year = DateTime.shift_zone!(DateTime.utc_now(), "America/Los_Angeles").year
    idempotency_key = "annual_access_review_#{year}"

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = perform_job(AnnualAccessReviewWorker, %{})

      assert [
               %Oban.Job{
                 args: %{
                   "recipient" => "webtech@ysc.org",
                   "idempotency_key" => ^idempotency_key,
                   "template" => "admin_access_review",
                   "params" => params
                 }
               }
             ] = all_enqueued(worker: EmailNotifier)

      assert params["admin_count"] == 1
      assert params["volunteer_count"] == 1

      emails = Enum.map(params["users"], & &1["email"])
      assert admin.email in emails
      assert volunteer.email in emails
      refute member.email in emails

      admin_row = Enum.find(params["users"], &(&1["email"] == admin.email))
      assert admin_row["name"] == "Astrid Lind"
      assert admin_row["role"] == "Admin"
      assert admin_row["board_position"] == "Tahoe Cabin Master"
      assert admin_row["last_sign_in"] == "Never"
    end)
  end
end
