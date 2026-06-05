defmodule Ysc.StaffPreview do
  @moduledoc """
  Shared helpers for staff-only preview of unpublished content.
  """

  alias Ysc.Accounts.User

  @doc """
  Returns whether `viewer` may load unpublished posts or events for staff preview.
  """
  def staff_content_preview?(%User{role: role})
      when role in [:admin, :volunteer],
      do: true

  def staff_content_preview?(_), do: false
end
