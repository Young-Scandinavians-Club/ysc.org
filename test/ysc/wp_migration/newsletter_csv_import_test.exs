defmodule Ysc.WpMigration.NewsletterCsvImportTest do
  use Ysc.DataCase, async: false

  alias Ysc.Accounts
  alias Ysc.Newsletter
  alias Ysc.Newsletter.Subscriber
  alias Ysc.Repo
  alias Ysc.WpMigration.NewsletterCsvImport

  import Ysc.AccountsFixtures

  setup do
    dir =
      System.tmp_dir!()
      |> Path.join("nl-csv-#{System.unique_integer()}")
      |> tap(&File.mkdir_p!/1)

    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp write_csv(dir, rows) do
    path = Path.join(dir, "newsletter_emails.csv")

    header =
      ~s("Email","First name","Last name","Subscription time","Confirmation time","List status","Global status","List"\n)

    body =
      Enum.map_join(rows, "\n", fn row ->
        [
          row.email,
          row[:first_name] || "",
          row[:last_name] || "",
          row[:subscription_time] || "2020-01-15 10:00:00",
          "",
          row[:list_status] || "subscribed",
          row[:global_status] || "subscribed",
          "Emailable"
        ]
        |> Enum.map_join(",", &~s("#{&1}"))
      end)

    File.write!(path, header <> body <> "\n")
    path
  end

  test "creates missing active subscribers and skips inactive rows", %{dir: dir} do
    email = "csv-nl-#{System.unique_integer()}@example.com"

    path =
      write_csv(dir, [
        %{
          email: email,
          first_name: "Ada",
          last_name: "Lovelace",
          subscription_time: "2019-06-01 12:00:00"
        },
        %{
          email: "inactive-#{System.unique_integer()}@example.com",
          list_status: "subscribed",
          global_status: "inactive"
        },
        %{
          email: "unsub-#{System.unique_integer()}@example.com",
          list_status: "unsubscribed",
          global_status: "unsubscribed"
        }
      ])

    assert {:ok, stats} = NewsletterCsvImport.run(path)
    assert stats.created == 1
    assert stats.failed == 0

    subscriber = Newsletter.get_subscriber_by_email(email)

    assert %Subscriber{
             subscribed: true,
             first_name: "Ada",
             last_name: "Lovelace"
           } = subscriber

    assert subscriber.source == "wp_newsletter_csv"
    assert subscriber.subscribed_at == ~U[2019-06-01 12:00:00Z]
    assert subscriber.metadata["wp_newsletter_csv"] == true
  end

  test "is idempotent for emails that already exist", %{dir: dir} do
    email = "csv-nl-existing-#{System.unique_integer()}@example.com"

    {:ok, existing} =
      Newsletter.subscribe(email,
        source: "wp_migration",
        first_name: "Old",
        skip_email_validation: true
      )

    path =
      write_csv(dir, [
        %{email: email, first_name: "New", last_name: "Name"}
      ])

    assert {:ok, stats} = NewsletterCsvImport.run(path)
    assert stats.created == 0
    assert stats.unchanged == 1

    reloaded = Repo.get!(Subscriber, existing.id)
    assert reloaded.subscribed == true
    assert reloaded.source == "wp_migration"
    assert reloaded.first_name == "Old"
    assert reloaded.last_name == "Name"
  end

  test "links an existing user and skips MX validation for trusted CSV", %{
    dir: dir
  } do
    domain = "mx-reject-#{System.unique_integer([:positive])}.example.org"
    email = "member@#{domain}"
    user = user_fixture(%{email: email, first_name: "Pat", last_name: "Member"})

    # Registration may already create a newsletter row; remove it so this
    # exercises CSV create + user link with skip_email_validation.
    case Newsletter.get_subscriber_by_email(email) do
      nil -> :ok
      existing -> Repo.delete!(existing)
    end

    path =
      write_csv(dir, [
        %{email: email, first_name: "Pat", last_name: "Member"}
      ])

    assert {:ok, stats} = NewsletterCsvImport.run(path)
    assert stats.created == 1

    subscriber = Newsletter.get_subscriber_by_email(email)
    assert subscriber.user_id == user.id
    assert Accounts.get_user_by_email(email).id == user.id
  end

  test "dry run does not write", %{dir: dir} do
    email = "csv-nl-dry-#{System.unique_integer()}@example.com"
    path = write_csv(dir, [%{email: email}])

    assert {:ok, stats} = NewsletterCsvImport.run(path, dry_run: true)
    assert stats.created == 1
    assert Newsletter.get_subscriber_by_email(email) == nil
  end
end
