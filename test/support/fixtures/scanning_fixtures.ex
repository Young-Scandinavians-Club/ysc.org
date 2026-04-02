defmodule Ysc.ScanningFixtures do
  @moduledoc """
  Test helpers for creating scanning-related entities.
  """

  alias Ysc.Scanning

  def scan_session_fixture(attrs \\ %{}) do
    user =
      attrs[:created_by] || Ysc.AccountsFixtures.user_fixture(%{role: "admin"})

    base_attrs = %{
      name: "Test Session #{System.unique_integer()}",
      type: :membership,
      created_by_id: user.id
    }

    attrs = Map.merge(base_attrs, Enum.into(attrs, %{}))

    {:ok, session} = Scanning.create_session(attrs)
    Scanning.get_session!(session.id)
  end

  def event_scan_session_fixture(event, admin_user, attrs \\ %{}) do
    base_attrs = %{
      name: "Event Session #{System.unique_integer()}",
      type: :event,
      event_id: event.id,
      created_by_id: admin_user.id
    }

    attrs = Map.merge(base_attrs, Enum.into(attrs, %{}))

    {:ok, session} = Scanning.create_session(attrs)
    Scanning.get_session!(session.id)
  end

  def event_membership_session_fixture(event, admin_user, attrs \\ %{}) do
    base_attrs = %{
      name: "Membership Check-in #{System.unique_integer()}",
      type: :event_membership,
      event_id: event.id,
      created_by_id: admin_user.id
    }

    attrs = Map.merge(base_attrs, Enum.into(attrs, %{}))

    {:ok, session} = Scanning.create_session(attrs)
    Scanning.get_session!(session.id)
  end
end
