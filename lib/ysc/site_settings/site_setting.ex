defmodule Ysc.SiteSettings.SiteSetting do
  @moduledoc """
  Site setting schema and changesets.

  Defines the SiteSetting database schema, validations, and changeset functions
  for site setting data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "site_settings" do
    field :group, :string
    field :name, :string
    field :value, :string

    timestamps()
  end

  def site_setting_changeset(setting, attrs, _opts \\ []) do
    setting |> cast(attrs, [:group, :name, :value])
  end
end
