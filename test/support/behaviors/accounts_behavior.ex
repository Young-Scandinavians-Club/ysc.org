defmodule Ysc.Accounts.Behaviour do
  @moduledoc """
  Behavior for Accounts context mocking in tests.

  Defines callbacks for mocking Accounts context operations in test scenarios.
  """
  @callback get_signup_application_submission_date(integer()) :: %{
              submit_date: DateTime.t(),
              timezone: String.t() | nil
            }
end
