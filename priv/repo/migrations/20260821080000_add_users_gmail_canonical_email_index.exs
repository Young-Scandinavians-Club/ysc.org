defmodule Ysc.Repo.Migrations.AddUsersGmailCanonicalEmailIndex do
  @moduledoc """
  Indexes the Gmail/Googlemail canonical form of `users.email` so alias
  lookup does not Seq Scan the users table.

  ## Problem

  `User.get_by_canonical_email/1` (login, OAuth, signup collision checks)
  used `ILIKE '%@gmail.com'` then `Enum.find` in Elixir. CI EXPLAIN on
  PR #1073 showed:

      Seq Scan on users (Filter: email ~~* '%@gmail.com'::citext)

  Every new Gmail signup that is not an exact email hit still loaded every
  Gmail member row (including `hashed_password`) into the app.

  ## Solution

  Match `Ysc.Accounts.Email.normalize/1` in SQL (strip dots, then
  plus-tags, keep domain) and btree-index that expression for equality
  lookups of the already-normalized address.
  """
  use Ecto.Migration

  def change do
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
            """,
            "DROP INDEX users_gmail_canonical_email_index"
  end
end
