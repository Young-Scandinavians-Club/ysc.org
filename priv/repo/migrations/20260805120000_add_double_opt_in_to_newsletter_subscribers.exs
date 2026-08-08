defmodule Ysc.Repo.Migrations.AddDoubleOptInToNewsletterSubscribers do
  use Ecto.Migration

  def change do
    alter table(:newsletter_subscribers) do
      add :confirmation_token, :string, null: true
      add :confirmed_at, :utc_datetime, null: true
      # A pending double opt-in signup has subscribed: false and no
      # subscribed_at yet — the subscribed_at_set_when_subscribed check
      # constraint (below) already enforces it's set once subscribed: true.
      modify :subscribed_at, :utc_datetime, null: true
    end

    create unique_index(:newsletter_subscribers, [:confirmation_token])

    # Every subscriber created before this feature existed predates double
    # opt-in and was added under the old single-opt-in behavior. Treat them
    # as already confirmed so `confirmed_at IS NULL` becomes a reliable
    # signal that means exclusively "pending, never confirmed."
    execute(
      "UPDATE newsletter_subscribers SET confirmed_at = subscribed_at WHERE confirmed_at IS NULL AND subscribed_at IS NOT NULL",
      ""
    )
  end
end
