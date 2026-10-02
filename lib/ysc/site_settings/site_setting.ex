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
    setting
    |> cast(attrs, [:group, :name, :value])
    |> validate_social_url_value()
  end

  defp validate_social_url_value(changeset) do
    name = get_field(changeset, :name)
    value = get_field(changeset, :value)

    if Ysc.SiteSettings.SocialUrl.social_setting?(name) do
      trimmed = if is_binary(value), do: String.trim(value), else: value

      changeset =
        if is_binary(trimmed) and trimmed != value do
          put_change(changeset, :value, trimmed)
        else
          changeset
        end

      case Ysc.SiteSettings.SocialUrl.validate(name, trimmed) do
        :ok ->
          changeset

        {:error, message} ->
          add_error(changeset, :value, message)
      end
    else
      changeset
    end
  end
end
