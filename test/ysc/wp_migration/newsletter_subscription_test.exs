defmodule Ysc.WpMigration.NewsletterSubscriptionTest do
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Accounts.User
  alias Ysc.Newsletter
  alias Ysc.Newsletter.Subscriber
  alias Ysc.Repo
  alias Ysc.WpMigration.Load

  @moduletag skip_settings_setup: true

  setup do
    export_dir =
      System.tmp_dir!()
      |> Path.join("wp-export-#{System.unique_integer()}")
      |> tap(&File.mkdir_p!/1)

    on_exit(fn -> File.rm_rf!(export_dir) end)

    {:ok, export_dir: export_dir}
  end

  defp write_users_json(export_dir, rows) do
    export_dir
    |> Path.join("users.json")
    |> File.write!(Jason.encode!(rows))
  end

  describe "load_users newsletter subscription" do
    test "subscribes newly imported users to the newsletter", %{
      export_dir: export_dir
    } do
      email = "wp-newsletter-#{System.unique_integer()}@example.com"

      write_users_json(export_dir, [
        %{
          "wp_user_id" => "wp-1",
          "email" => email,
          "first_name" => "Nordic",
          "last_name" => "Member",
          "user_registered" => "2020-01-15 10:00:00",
          "role" => "subscriber"
        }
      ])

      assert {:ok, _} =
               Load.run(
                 export_dir: export_dir,
                 upload_media: false,
                 only_emails: [email]
               )

      user = Repo.get_by!(User, email: email)
      subscriber = Newsletter.get_subscriber_by_email(email)

      assert %Subscriber{
               user_id: user_id,
               subscribed: true,
               source: "wp_migration",
               first_name: "Nordic",
               last_name: "Member"
             } = subscriber

      assert user_id == user.id
      assert subscriber.metadata["wp_migration"] == true
    end

    test "subscribes existing users on re-import", %{export_dir: export_dir} do
      email = "wp-newsletter-existing-#{System.unique_integer()}@example.com"

      user =
        user_fixture(%{email: email, first_name: "Henrik", last_name: "Member"})

      write_users_json(export_dir, [
        %{
          "wp_user_id" => "wp-2",
          "email" => email,
          "first_name" => "Henrik",
          "last_name" => "Member",
          "user_registered" => "2020-01-15 10:00:00",
          "role" => "subscriber"
        }
      ])

      assert {:ok, _} =
               Load.run(
                 export_dir: export_dir,
                 upload_media: false,
                 only_emails: [email]
               )

      subscriber = Newsletter.get_subscriber_by_email(email)

      assert %Subscriber{
               user_id: user_id,
               subscribed: true,
               source: "wp_migration"
             } = subscriber

      assert user_id == user.id
    end

    test "re-import is idempotent for newsletter subscribers", %{
      export_dir: export_dir
    } do
      email = "wp-newsletter-idempotent-#{System.unique_integer()}@example.com"

      write_users_json(export_dir, [
        %{
          "wp_user_id" => "wp-3",
          "email" => email,
          "first_name" => "Repeat",
          "last_name" => "Import",
          "user_registered" => "2020-01-15 10:00:00",
          "role" => "subscriber"
        }
      ])

      assert {:ok, _} =
               Load.run(
                 export_dir: export_dir,
                 upload_media: false,
                 only_emails: [email]
               )

      assert {:ok, _} =
               Load.run(
                 export_dir: export_dir,
                 upload_media: false,
                 only_emails: [email]
               )

      assert Repo.aggregate(
               from(s in Subscriber, where: s.email == ^email),
               :count
             ) == 1
    end
  end
end
