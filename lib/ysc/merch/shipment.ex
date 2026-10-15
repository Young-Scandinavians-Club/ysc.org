defmodule Ysc.Merch.Shipment do
  @moduledoc """
  One parcel of a merch order, as reported by Printful. An order can ship in
  several parcels, and a parcel can be reshipped.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "merch_shipments" do
    field :printful_shipment_id, :integer
    field :carrier, :string
    field :service, :string
    field :tracking_number, :string
    field :tracking_url, :string

    field :status, Ecto.Enum,
      values: [:shipped, :delivered, :returned],
      default: :shipped

    field :reshipment, :boolean, default: false
    field :shipped_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :notified_at, :utc_datetime

    belongs_to :order, Ysc.Merch.Order

    timestamps()
  end

  def changeset(shipment, attrs) do
    shipment
    |> cast(attrs, [
      :order_id,
      :printful_shipment_id,
      :carrier,
      :service,
      :tracking_number,
      :tracking_url,
      :status,
      :reshipment,
      :shipped_at,
      :delivered_at
    ])
    |> validate_required([:order_id, :printful_shipment_id])
    |> validate_length(:tracking_url, max: 1024)
    |> unique_constraint(:printful_shipment_id)
    |> foreign_key_constraint(:order_id)
  end

  @doc """
  Whether `tracking_url` is safe to put in a link: an http(s) URL. Printful's
  value is shown to members, so anything else (e.g. `javascript:`) is dropped.
  """
  def safe_tracking_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) ->
        url

      _ ->
        nil
    end
  end

  def safe_tracking_url(_), do: nil
end
