defmodule Ysc.Repo.Migrations.SeedNewsletterSubscribersFromUsers do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto"

    execute """
    INSERT INTO newsletter_subscribers (
      id,
      email,
      user_id,
      first_name,
      last_name,
      subscribed,
      subscription_token,
      source,
      metadata,
      subscribed_at,
      unsubscribed_at,
      inserted_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      u.email,
      u.id,
      u.first_name,
      u.last_name,
      true,
      replace(replace(encode(gen_random_bytes(32), 'base64'), '+', '-'), '/', '_'),
      'migration',
      '{}',
      NOW() AT TIME ZONE 'UTC',
      NULL,
      NOW() AT TIME ZONE 'UTC',
      NOW() AT TIME ZONE 'UTC'
    FROM users u
    WHERE u.newsletter_notifications = true
    ON CONFLICT (email) DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM newsletter_subscribers WHERE source = 'migration'"
  end
end
