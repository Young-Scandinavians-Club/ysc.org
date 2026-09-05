defmodule YscWeb.Emails.SaveTheDateAvailableTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Repo
  alias YscWeb.Emails.SaveTheDateAvailable

  describe "get_template_name/0, get_subject/1, URLs" do
    test "template name and notification settings URL" do
      assert SaveTheDateAvailable.get_template_name() ==
               "save_the_date_available"

      assert YscWeb.Emails.Helpers.notification_settings_url() =~
               "/users/notifications"
    end

    test "get_subject/1 for nil event uses generic copy" do
      assert SaveTheDateAvailable.get_subject(nil) ==
               "[YSC] An event you saved is now available"
    end

    test "get_subject/1 interpolates title and subject templates avoid registration jargon" do
      event = %Ysc.Events.Event{title: "Midsummer Gala"}
      subject = SaveTheDateAvailable.get_subject(event)

      assert subject =~ "[YSC]"
      assert subject =~ "Midsummer Gala"

      for template <- SaveTheDateAvailable.subject_templates() do
        refute template =~ "registration"
        assert template =~ "{title}" or template =~ "tickets"
      end
    end

    test "event_url/1 builds events path" do
      id = Ecto.ULID.generate()
      assert YscWeb.Emails.Helpers.event_url(id) =~ "/events/#{id}"
    end
  end

  describe "prepare_email_data/2" do
    setup do
      user = user_fixture()
      organizer = user_fixture()
      {:ok, event} = Events.create_event(base_event_attrs(organizer.id))
      event = Repo.preload(event, [:organizer, :cover_image])

      %{user: user, event: event}
    end

    test "builds data when associations are preloaded", %{
      user: user,
      event: event
    } do
      data = SaveTheDateAvailable.prepare_email_data(event, user)

      assert data.first_name == user.first_name ||
               data.first_name == "Valued Member"

      assert data.event.title == event.title
      assert data.event_url =~ event.id
      assert data.notification_settings_url =~ "/users/notifications"
    end

    test "prepare_shared_email_data omits first_name", %{
      user: user,
      event: event
    } do
      shared = SaveTheDateAvailable.prepare_shared_email_data(event)
      refute Map.has_key?(shared, :first_name)

      data = SaveTheDateAvailable.prepare_email_data(event, user)
      assert data == Map.put(shared, :first_name, data.first_name)
    end

    test "loads event from database when organizer not loaded", %{user: user} do
      organizer = user_fixture()

      {:ok, event} =
        Events.create_event(
          Map.merge(base_event_attrs(organizer.id), %{
            title: "Lazy Load Event #{System.unique_integer([:positive])}"
          })
        )

      bare = Repo.get!(Ysc.Events.Event, event.id)

      refute Ecto.assoc_loaded?(bare.organizer)

      data = SaveTheDateAvailable.prepare_email_data(bare, user)

      assert data.event.title == bare.title
      assert data.event_url =~ bare.id
    end

    test "uses Valued Member when user first_name is nil", %{event: event} do
      user =
        user_fixture()
        |> Ecto.Changeset.change(%{first_name: nil})
        |> Repo.update!()

      data = SaveTheDateAvailable.prepare_email_data(event, user)
      assert data.first_name == "Valued Member"
    end

    test "raises when event is nil", %{user: user} do
      assert_raise ArgumentError, fn ->
        Ysc.Test.Invoke.call(SaveTheDateAvailable, :prepare_email_data, [
          nil,
          user
        ])
      end
    end

    test "raises when user is nil", %{event: event} do
      assert_raise ArgumentError, fn ->
        Ysc.Test.Invoke.call(SaveTheDateAvailable, :prepare_email_data, [
          event,
          nil
        ])
      end
    end

    test "format_event_datetime is nil when start_date is nil", %{user: user} do
      organizer = user_fixture()

      {:ok, event} =
        Events.create_event(
          Map.merge(base_event_attrs(organizer.id), %{
            title: "No date #{System.unique_integer([:positive])}",
            start_date: nil
          })
        )

      event = Repo.preload(event, [:organizer, :cover_image])

      data = SaveTheDateAvailable.prepare_email_data(event, user)
      assert data.event_date_time == nil
    end

    test "formats date-only when start_time is nil", %{user: user} do
      organizer = user_fixture()

      {:ok, event} =
        Events.create_event(
          Map.merge(base_event_attrs(organizer.id), %{
            title: "Date only #{System.unique_integer([:positive])}",
            start_date: DateTime.new!(~D[2026-07-15], ~T[00:00:00], "Etc/UTC"),
            start_time: nil
          })
        )

      event = Repo.preload(event, [:organizer, :cover_image])

      data = SaveTheDateAvailable.prepare_email_data(event, user)
      assert data.event_date_time =~ "July"
      assert data.event_date_time =~ "2026"
      refute data.event_date_time =~ " at "
    end

    test "strips HTML from event description", %{user: user} do
      organizer = user_fixture()

      {:ok, event} =
        Events.create_event(
          Map.merge(base_event_attrs(organizer.id), %{
            title: "Desc #{System.unique_integer([:positive])}",
            description: "<p>Hello <b>World</b></p>"
          })
        )

      event = Repo.preload(event, [:organizer, :cover_image])

      data = SaveTheDateAvailable.prepare_email_data(event, user)
      assert data.event.description == "Hello World"
    end
  end

  describe "render/1" do
    test "renders HTML for minimal assigns" do
      data =
        SaveTheDateAvailable.prepare_email_data(
          event_fixture() |> Repo.preload([:organizer, :cover_image]),
          user_fixture()
        )

      html = SaveTheDateAvailable.render(data)

      assert html =~ "ticket" or html =~ "event" or html =~ "YSC"
      assert is_binary(html)
    end
  end

  defp base_event_attrs(organizer_id) do
    %{
      title: "Save the Date #{System.unique_integer()}",
      description: "Test",
      state: :published,
      organizer_id: organizer_id,
      start_date:
        DateTime.add(DateTime.utc_now(), 10, :day) |> DateTime.truncate(:second),
      end_date:
        DateTime.add(DateTime.utc_now(), 11, :day) |> DateTime.truncate(:second),
      max_attendees: 100,
      published_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end
end
