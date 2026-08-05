defmodule Ysc.Newsletter.Subscriber do
  @moduledoc """
  Schema for newsletter subscribers.

  Email is stored with citext (case-insensitive) in the database.
  subscription_token is used for public unsubscribe links.
  confirmation_token is used for double opt-in confirmation links;
  confirmed_at is nil exclusively for anonymous signups still awaiting
  confirmation (trusted/authenticated subscribe paths are auto-confirmed).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User

  @derive {
    Flop.Schema,
    filterable: [:email, :subscribed],
    sortable: [:email, :subscribed_at, :source, :first_name, :last_name],
    default_limit: 20,
    max_limit: 100,
    default_order: %{order_by: [:subscribed_at], order_directions: [:desc]}
  }

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "newsletter_subscribers" do
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :subscribed, :boolean, default: true
    field :subscription_token, :string
    field :confirmation_token, :string
    field :confirmed_at, :utc_datetime
    field :source, :string
    field :metadata, :map, default: %{}
    field :subscribed_at, :utc_datetime
    field :unsubscribed_at, :utc_datetime

    belongs_to :user, User

    timestamps()
  end

  @doc """
  Changeset for creating a new subscriber.
  Sets subscription_token and subscribed_at if not present.

  `subscribed_at` is only required when `subscribed` is true (see
  `maybe_validate_subscribed_at/1`) — a pending double opt-in signup is
  created with `subscribed: false` and no `subscribed_at` yet.
  """
  def create_changeset(subscriber, attrs) do
    subscriber
    |> cast(attrs, [
      :email,
      :user_id,
      :first_name,
      :last_name,
      :subscribed,
      :subscription_token,
      :confirmation_token,
      :confirmed_at,
      :source,
      :metadata,
      :subscribed_at,
      :unsubscribed_at
    ])
    |> validate_required([:email, :subscription_token])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:email, max: 255)
    |> validate_length(:first_name, max: 255)
    |> validate_length(:last_name, max: 255)
    |> validate_length(:subscription_token, max: 255)
    |> validate_length(:confirmation_token, max: 255)
    |> validate_length(:source, max: 255)
    |> unique_constraint(:email)
    |> unique_constraint(:subscription_token)
    |> unique_constraint(:confirmation_token)
    |> maybe_validate_subscribed_at()
  end

  @doc """
  Changeset for updating an existing subscriber (e.g. link user_id, toggle subscribed).
  """
  def update_changeset(subscriber, attrs) do
    subscriber
    |> cast(attrs, [
      :email,
      :user_id,
      :first_name,
      :last_name,
      :subscribed,
      :confirmation_token,
      :confirmed_at,
      :source,
      :metadata,
      :subscribed_at,
      :unsubscribed_at
    ])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:email, max: 255)
    |> validate_length(:first_name, max: 255)
    |> validate_length(:last_name, max: 255)
    |> validate_length(:confirmation_token, max: 255)
    |> validate_length(:source, max: 255)
    |> unique_constraint(:email)
    |> unique_constraint(:confirmation_token)
    |> maybe_validate_subscribed_at()
  end

  defp maybe_validate_subscribed_at(changeset) do
    subscribed = get_field(changeset, :subscribed)
    subscribed_at = get_field(changeset, :subscribed_at)

    if subscribed && is_nil(subscribed_at) do
      add_error(
        changeset,
        :subscribed_at,
        "must be set when subscribed is true"
      )
    else
      changeset
    end
  end

  @doc """
  Generates a secure random token for unsubscribe links.
  """
  def generate_subscription_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Generates a secure random token for double opt-in confirmation links.
  """
  def generate_confirmation_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
