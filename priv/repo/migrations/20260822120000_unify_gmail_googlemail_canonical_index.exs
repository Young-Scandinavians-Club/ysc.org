defmodule Ysc.Repo.Migrations.UnifyGmailGooglemailCanonicalIndex do
  @moduledoc """
  Rebuilds `users_gmail_canonical_email_index` so `@googlemail.com` is treated
  as `@gmail.com`, matching `Ysc.Accounts.Email.normalize/1`.

  Google delivers mail for both domains to the same inbox. Leaving them as
  distinct canonical forms allowed a second account for the same mailbox after
  the dotted/plus Gmail alias fix (PR #1073 / Finding 35).
  """
  use Ecto.Migration

  def up do
    execute "DROP INDEX IF EXISTS users_gmail_canonical_email_index"

    execute """
    CREATE INDEX users_gmail_canonical_email_index ON users (
      (
        split_part(
          regexp_replace(split_part(lower((email)::text), '@', 1), '[.]', '', 'g'),
          '+',
          1
        ) || '@' ||
        case
          when split_part(lower((email)::text), '@', 2) = 'googlemail.com'
            then 'gmail.com'
          else split_part(lower((email)::text), '@', 2)
        end
      )
    )
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS users_gmail_canonical_email_index"

    execute """
    CREATE INDEX users_gmail_canonical_email_index ON users (
      (
        split_part(
          regexp_replace(split_part(lower((email)::text), '@', 1), '[.]', '', 'g'),
          '+',
          1
        ) || '@' || split_part(lower((email)::text), '@', 2)
      )
    )
    """
  end
end
