defmodule Ysc.Newsletter.EmailEvent do
  @moduledoc """
  Schema for SES email tracking events (opens, clicks, bounces, complaints).

  Events are received via SNS webhook from AWS SES Configuration Sets.
  The `environment` field ensures prod and sandbox events (which share
  the same SES/SNS configuration) are stored and filtered correctly.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User
  alias Ysc.Newsletter.Edition
  alias Ysc.Newsletter.Subscriber

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "email_events" do
    field :event_type, :string
    field :email, :string
    field :environment, :string
    field :template, :string

    belongs_to :edition, Edition
    belongs_to :subscriber, Subscriber
    belongs_to :user, User

    field :bounce_type, :string
    field :bounce_sub_type, :string
    field :link_url, :string
    field :raw_payload, :map, default: %{}
    field :event_timestamp, :utc_datetime

    timestamps()
  end

  @valid_event_types ~w(open click bounce complaint send delivery)

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :event_type,
      :email,
      :environment,
      :template,
      :edition_id,
      :subscriber_id,
      :user_id,
      :bounce_type,
      :bounce_sub_type,
      :link_url,
      :raw_payload,
      :event_timestamp
    ])
    |> validate_required([:event_type, :email, :environment])
    |> validate_inclusion(:event_type, @valid_event_types)
    |> validate_length(:email, max: 255)
    |> validate_length(:environment, max: 50)
    |> validate_length(:template, max: 255)
    |> foreign_key_constraint(:edition_id)
    |> foreign_key_constraint(:subscriber_id)
    |> foreign_key_constraint(:user_id)
  end
end
