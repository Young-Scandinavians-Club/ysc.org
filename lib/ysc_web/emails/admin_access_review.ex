defmodule YscWeb.Emails.AdminAccessReview do
  @moduledoc """
  Email template for the annual admin/volunteer access review.

  Sent to the WebTech team every March 1 with every account that holds an
  admin or volunteer role, so access can be revoked for people who have left
  the board.
  """
  use MjmlEEx,
    mjml_template: "templates/admin_access_review.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [absolute_url: 1, format_datetime: 2]

  def get_template_name, do: "admin_access_review"

  def get_subject(year), do: "Annual Admin & Volunteer Access Review (#{year})"

  @doc """
  Builds template assigns from `Ysc.Accounts.AccessReview.list_privileged_users/0` rows.
  """
  def build_assigns(users, year) do
    rows = Enum.map(users, &build_row/1)

    %{
      year: year,
      admin_count: Enum.count(users, &(&1.role == :admin)),
      volunteer_count: Enum.count(users, &(&1.role == :volunteer)),
      has_users: rows != [],
      users: rows,
      admin_users_url: absolute_url("/admin/users")
    }
  end

  defp build_row(user) do
    %{
      name: String.trim("#{user.first_name} #{user.last_name}"),
      email: user.email,
      role: humanize(user.role),
      board_position: humanize(user.board_position) || "—",
      state: humanize(user.state),
      last_sign_in: format_datetime(user.last_sign_in_at, "Never"),
      edit_url: absolute_url("/admin/users/#{user.id}")
    }
  end

  defp humanize(nil), do: nil

  defp humanize(value) do
    value
    |> to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
