defmodule Ysc.Events.Event do
  @moduledoc """
  Event schema and changesets.

  Defines the Event database schema, validations, and changeset functions
  for event data manipulation.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ysc.ReferenceGenerator

  @reference_prefix "EVT"

  @derive {
    Flop.Schema,
    filterable: [
      :state,
      :organizer_id
    ],
    sortable: [:state, :title, :start_date, :organizer_name, :inserted_at],
    default_limit: 50,
    max_limit: 200,
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    },
    adapter_opts: [
      join_fields: [
        organizer_first: [
          binding: :organizer,
          field: :first_name,
          ecto_type: :string
        ],
        organizer_last: [
          binding: :organizer,
          field: :first_name,
          ecto_type: :string
        ]
      ],
      compound_fields: [
        organizer_name: [:organizer_first, :organizer_last]
      ]
    ]
  }

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "events" do
    field :reference_id, :string

    # Control publishing of the event
    # Draft: Not visible to the public
    # Published: Visible to the public
    field :state, Ysc.Events.EventState
    field :published_at, :utc_datetime
    field :publish_at, :utc_datetime

    # Who created the event (organizer)
    belongs_to :organizer, Ysc.Accounts.User,
      foreign_key: :organizer_id,
      references: :id

    field :title, :string
    # Short description that will be displayed in the event list
    # and in the calendar event tooltip
    field :description, :string

    # Optional: Puts a total limit on the number of attendees
    # across all ticket types if set to 0 or null then no limit
    # is enforced globally -- it will be enforced per ticet type instead.
    field :max_attendees, :integer
    # Virtual field for unlimited capacity checkbox
    field :unlimited_capacity, :boolean, virtual: true
    # Optional: Age restriction for the event
    # if null or 0 then no age restriction
    field :age_restriction, :integer

    # If true, the participants list will be shown on the event page to signed-in and approved members
    field :show_participants, :boolean, default: false

    # Detailed information about the event
    field :raw_details, :string
    # Cache for the rich content in the details sections
    field :rendered_details, :string

    # Required: A cover image for the event to show in the list
    belongs_to :cover_image, Ysc.Media.Image,
      foreign_key: :image_id,
      references: :id

    # When event starts
    field :start_date, :utc_datetime
    field :start_time, :time
    # When event ends (if null, then it's a single day event)
    field :end_date, :utc_datetime
    field :end_time, :time

    # Location fields
    # Name of the location (e.g., "Central Park")
    field :location_name, :string
    # Full address (e.g., "59th St and 5th Ave, New York, NY")
    field :address, :string
    # Latitude for map display
    field :latitude, :float
    # Longitude for map display
    field :longitude, :float
    # Optional: External ID from a mapping service (e.g., Google Place ID)
    field :place_id, :string

    has_many :faq_questions, Ysc.Events.FaqQuestion, on_replace: :delete
    has_many :agendas, Ysc.Events.Agenda, on_replace: :delete
    has_many :ticket_tiers, Ysc.Events.TicketTier, on_replace: :delete

    field :lock_version, :integer, default: 1

    timestamps()
  end

  @doc """
  Changeset for the event with validations.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :reference_id,
      :state,
      :published_at,
      :publish_at,
      :organizer_id,
      :title,
      :description,
      :max_attendees,
      :unlimited_capacity,
      :age_restriction,
      :raw_details,
      :rendered_details,
      :image_id,
      :location_name,
      :address,
      :latitude,
      :longitude,
      :place_id,
      :start_date,
      :start_time,
      :end_date,
      :end_time,
      :lock_version
    ])
    |> validate_required([
      :state,
      :organizer_id,
      :title
    ])
    |> validate_length(:title, max: 100)
    |> validate_length(:description, max: 200)
    |> handle_unlimited_capacity()
    |> put_reference_id()
    |> unique_constraint(:reference_id)
    |> validate_publish_dates()
    |> validate_start_end()
    |> optimistic_lock(:lock_version)
  end

  defp validate_start_end(changeset) do
    start_date = get_field(changeset, :start_date)
    start_time = get_field(changeset, :start_time)
    end_date = get_field(changeset, :end_date)
    end_time = get_field(changeset, :end_time)

    start_datetime = combine_date_time(start_date, start_time)
    end_datetime = combine_date_time(end_date, end_time)

    if start_datetime && end_datetime &&
         DateTime.compare(start_datetime, end_datetime) == :gt do
      add_error(changeset, :start_date, "must be before the end date and time")
    else
      changeset
    end
  end

  defp validate_publish_dates(changeset) do
    publish_at = get_field(changeset, :publish_at)
    start_date = get_field(changeset, :start_date)
    start_time = get_field(changeset, :start_time)

    start_datetime = combine_date_time(start_date, start_time)

    if publish_at && start_datetime &&
         DateTime.compare(publish_at, start_datetime) == :gt do
      add_error(
        changeset,
        :publish_at,
        "must be before the event start date and time"
      )
    else
      changeset
    end
  end

  defp combine_date_time(nil, _), do: nil
  defp combine_date_time(_, nil), do: nil

  defp combine_date_time(%DateTime{} = date, %Time{} = time) do
    naive_date = DateTime.to_naive(date)
    date_part = NaiveDateTime.to_date(naive_date)
    naive_datetime = NaiveDateTime.new!(date_part, time)
    DateTime.from_naive!(naive_datetime, "Etc/UTC")
  end

  defp combine_date_time(date, time)
       when not is_nil(date) and not is_nil(time) do
    NaiveDateTime.new!(date, time)
    |> DateTime.from_naive!("Etc/UTC")
  end

  defp combine_date_time(_, _), do: nil

  defp put_reference_id(changeset) do
    case get_field(changeset, :reference_id) do
      nil ->
        put_change(
          changeset,
          :reference_id,
          ReferenceGenerator.generate_reference_id(@reference_prefix)
        )

      _ ->
        changeset
    end
  end

  # Handle the unlimited_capacity virtual field
  defp handle_unlimited_capacity(changeset) do
    unlimited_capacity = get_field(changeset, :unlimited_capacity)

    case unlimited_capacity do
      true ->
        # If unlimited_capacity is true, set max_attendees to nil
        put_change(changeset, :max_attendees, nil)

      false ->
        # If unlimited_capacity is false and max_attendees is nil, set a default
        current_max_attendees = get_field(changeset, :max_attendees)

        if is_nil(current_max_attendees) do
          put_change(changeset, :max_attendees, 100)
        else
          changeset
        end

      _ ->
        # If unlimited_capacity is nil or not set, don't change max_attendees
        changeset
    end
  end
end
