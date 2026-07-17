defmodule Ysc.Events.EventTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Events.Event

  setup do
    %{organizer: user_fixture()}
  end

  describe "changeset/2" do
    test "adds error when combined start is after end", %{organizer: organizer} do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          start_date: ~U[2025-06-11 10:00:00Z],
          start_time: ~T[10:00:00],
          end_date: ~U[2025-06-10 10:00:00Z],
          end_time: ~T[10:00:00]
        })

      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :start_date)
    end

    test "adds error when publish_at is after event start", %{
      organizer: organizer
    } do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          start_date: ~U[2025-06-10 10:00:00Z],
          start_time: ~T[10:00:00],
          publish_at: ~U[2025-06-11 12:00:00Z]
        })

      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :publish_at)
    end

    test "accepts valid partiful.com https link", %{organizer: organizer} do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          partiful_link: "  https://partiful.com/e/abc123  "
        })

      assert cs.valid?

      assert Ecto.Changeset.get_field(cs, :partiful_link) ==
               "https://partiful.com/e/abc123"
    end

    test "rejects partiful link that is not on partiful.com", %{
      organizer: organizer
    } do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          partiful_link: "https://example.com/foo"
        })

      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :partiful_link)
    end

    test "rejects malformed partiful link", %{organizer: organizer} do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          partiful_link: "not-a-url"
        })

      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :partiful_link)
    end

    test "strips HTML from description", %{organizer: organizer} do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          description: "<b>Hello</b>"
        })

      assert Ecto.Changeset.get_field(cs, :description) == "Hello"
    end

    test "trims whitespace from description after stripping HTML", %{
      organizer: organizer
    } do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          description: "  <p>Preview copy</p>  \n"
        })

      assert Ecto.Changeset.get_field(cs, :description) == "Preview copy"
    end

    test "preserves ampersands in description", %{organizer: organizer} do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          description: "food & drinks at The Junction"
        })

      assert Ecto.Changeset.get_field(cs, :description) ==
               "food & drinks at The Junction"
    end

    test "unlimited_capacity true clears max_attendees", %{organizer: organizer} do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          unlimited_capacity: true,
          max_attendees: 50
        })

      assert Ecto.Changeset.get_field(cs, :max_attendees) == nil
    end

    test "unlimited_capacity false with nil max_attendees defaults to 100", %{
      organizer: organizer
    } do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          unlimited_capacity: false,
          max_attendees: nil
        })

      assert Ecto.Changeset.get_field(cs, :max_attendees) == 100
    end

    test "unlimited_capacity false keeps explicit max_attendees", %{
      organizer: organizer
    } do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          unlimited_capacity: false,
          max_attendees: 42
        })

      assert Ecto.Changeset.get_field(cs, :max_attendees) == 42
    end

    test "preserves explicit reference_id when provided", %{
      organizer: organizer
    } do
      cs =
        Event.changeset(%Event{}, %{
          state: :draft,
          organizer_id: organizer.id,
          title: "T",
          reference_id: "EVT-CUSTOM-1"
        })

      assert Ecto.Changeset.get_field(cs, :reference_id) == "EVT-CUSTOM-1"
    end
  end
end
