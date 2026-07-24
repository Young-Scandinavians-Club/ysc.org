defmodule Ysc.Newsletter.Notice do
  @moduledoc """
  Schema for a reusable newsletter notice (HTML snippet) that can be inserted
  into an edition's intro text.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "newsletter_notices" do
    field :name, :string
    field :body, :string

    belongs_to :creator, User

    timestamps()
  end

  @doc """
  Changeset for creating or updating a saved notice.
  """
  def changeset(notice, attrs) do
    notice
    |> cast(attrs, [:name, :body])
    |> scrub_body()
    |> validate_required([:name, :body])
    |> validate_length(:name, max: 255)
    |> validate_length(:body, max: 50_000)
  end

  defp scrub_body(changeset) do
    case get_change(changeset, :body) do
      nil ->
        changeset

      body when is_binary(body) ->
        scrubbed = HtmlSanitizeEx.Scrubber.scrub(body, Ysc.TrixScrubber)
        put_change(changeset, :body, scrubbed)

      _ ->
        changeset
    end
  end
end
