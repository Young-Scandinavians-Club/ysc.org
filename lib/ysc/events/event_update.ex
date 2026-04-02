defmodule Ysc.Events.EventUpdate do
  @moduledoc """
  Schema for event updates that admins can send to all attendees.

  Stores the update content and metadata about when it was sent and to how many recipients.
  Optionally displayed on the public event details page.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "event_updates" do
    belongs_to :event, Ysc.Events.Event
    belongs_to :sent_by, Ysc.Accounts.User, foreign_key: :sent_by_id

    field :title, :string
    field :raw_body, :string
    field :rendered_body, :string
    field :show_on_event_page, :boolean, default: false
    field :sent_at, :utc_datetime
    field :recipient_count, :integer

    timestamps()
  end

  def changeset(event_update, attrs) do
    event_update
    |> cast(attrs, [:title, :raw_body, :rendered_body, :show_on_event_page])
    |> validate_required([:raw_body, :rendered_body])
    |> validate_length(:title, max: 200)
    |> validate_rendered_body_has_content()
  end

  defp validate_rendered_body_has_content(changeset) do
    validate_change(changeset, :rendered_body, fn :rendered_body, value ->
      stripped =
        (value || "")
        |> HtmlSanitizeEx.strip_tags()
        |> String.replace(~r/[\s\x{00a0}]+/u, "")

      if stripped == "",
        do: [rendered_body: "message body cannot be empty"],
        else: []
    end)
  end
end
