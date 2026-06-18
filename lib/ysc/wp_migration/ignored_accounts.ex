defmodule Ysc.WpMigration.IgnoredAccounts do
  @moduledoc """
  WordPress backup accounts that should be omitted from migration export/load.

  These are legacy WordPress test/service accounts, not real club members.
  """

  require Ysc.Logging

  alias Ysc.Accounts.Email

  @ignored_emails MapSet.new([
                    "joshua@jbrost.com",
                    "help@getflywheel.com",
                    "webtech@ysc.org",
                    "dev@myworks.software"
                  ])

  @doc """
  Returns true when the email belongs to an ignored WordPress account.
  """
  def ignored_email?(email) when is_binary(email) do
    MapSet.member?(@ignored_emails, Email.normalize(email))
  end

  def ignored_email?(_), do: false

  @doc """
  Returns true when a migration user/application row should be skipped.
  """
  def ignored_user?(row) when is_map(row) do
    ignored_email?(row["email"]) or row["display_name"] == "JoshTestUser"
  end

  def ignored_user?(_), do: false

  @doc """
  Drops ignored users from an export/load user list and logs what was skipped.
  """
  def reject_users(users) when is_list(users) do
    {kept, ignored} = Enum.split_with(users, &(not ignored_user?(&1)))

    if ignored != [] do
      Ysc.Logging.info(
        "[WP Migration] Skipping #{length(ignored)} ignored WordPress account(s)",
        emails: Enum.map(ignored, & &1["email"])
      )
    end

    kept
  end

  @doc """
  Builds a `MapSet` of `wp_user_id` values for ignored users in `users`.
  """
  def ignored_wp_user_ids(users) when is_list(users) do
    users
    |> Enum.filter(&ignored_user?/1)
    |> Enum.map(& &1["wp_user_id"])
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @doc """
  Drops rows whose `field` value is an ignored `wp_user_id`.
  """
  def reject_by_wp_user_id(rows, ignored_wp_user_ids, field)
      when is_list(rows) do
    if MapSet.size(ignored_wp_user_ids) == 0 do
      rows
    else
      Enum.reject(rows, fn row ->
        MapSet.member?(ignored_wp_user_ids, row[field])
      end)
    end
  end

  @doc """
  Drops user/application rows for ignored accounts.
  """
  def reject_user_rows(rows) when is_list(rows) do
    Enum.reject(rows, &ignored_user?/1)
  end
end
