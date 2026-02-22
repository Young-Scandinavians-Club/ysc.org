defmodule Ysc.MessagesTest do
  @moduledoc """
  Tests for Ysc.Messages context module.

  Idempotency contract:
  - A (message_type, idempotency_key, message_template) triplet must produce
    exactly ONE send regardless of how many times the function is called.
  - The pre-check path (record already exists) must short-circuit before
    touching the mailer / SMS client.
  - Keys are scoped: same key with a different template, or same key with a
    different message_type, are treated as independent sends.
  """
  use Ysc.DataCase, async: true

  import Ecto.Query
  import Swoosh.TestAssertions

  alias Ysc.Messages
  alias Ysc.Messages.MessageIdempotency
  import Ysc.AccountsFixtures

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  # Builds a minimal Swoosh email struct suitable for use with run_send_message_idempotent.
  defp test_email(opts \\ []) do
    recipient = Keyword.get(opts, :to, "test@example.com")
    subj = Keyword.get(opts, :subject, "Test Subject")

    Swoosh.Email.new()
    |> Swoosh.Email.to(recipient)
    |> Swoosh.Email.from({"YSC Test", "noreply@ysc.org"})
    |> Swoosh.Email.subject(subj)
    |> Swoosh.Email.html_body("<p>Test body</p>")
    |> Swoosh.Email.text_body("Test body")
  end

  # Builds attrs for run_send_message_idempotent.
  defp email_attrs(key, template \\ "booking_confirmation", user_id \\ nil) do
    %{
      message_type: :email,
      idempotency_key: key,
      message_template: template,
      params: %{},
      email: "test@example.com",
      rendered_message: "<p>Test body</p>",
      user_id: user_id
    }
  end

  # Builds attrs for run_send_sms_idempotent.
  defp sms_attrs(key, template \\ "booking_checkin_reminder", user_id \\ nil) do
    %{
      message_type: :sms,
      idempotency_key: key,
      message_template: template,
      params: %{},
      phone_number: "12065551234",
      rendered_message: "[YSC] Test SMS message.",
      user_id: user_id
    }
  end

  # Counts idempotency records for a given key.
  defp count_records_for_key(key) do
    Ysc.Repo.one(
      from m in MessageIdempotency,
        where: m.idempotency_key == ^key,
        select: count()
    )
  end

  # ---------------------------------------------------------------------------
  # run_send_message_idempotent/2  (email)
  # ---------------------------------------------------------------------------

  describe "run_send_message_idempotent/2 - first-time send" do
    test "sends the email and creates exactly one idempotency record" do
      key = "em_first_#{System.unique_integer()}"

      assert {:ok, _email} =
               Messages.run_send_message_idempotent(
                 test_email(),
                 email_attrs(key)
               )

      assert_email_sent(subject: "Test Subject")
      assert count_records_for_key(key) == 1
    end

    test "record contains the correct fields" do
      key = "em_fields_#{System.unique_integer()}"
      template = "booking_confirmation"

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 test_email(),
                 email_attrs(key, template)
               )

      record = Ysc.Repo.get_by(MessageIdempotency, idempotency_key: key)
      assert record.message_type == :email
      assert record.message_template == template
      assert record.email == "test@example.com"
    end
  end

  describe "run_send_message_idempotent/2 - duplicate handling" do
    test "second call with the same key returns {:ok, email} without sending" do
      key = "em_dup_#{System.unique_integer()}"
      email = test_email()
      attrs = email_attrs(key)

      # First send – email delivered, record committed.
      assert {:ok, _} = Messages.run_send_message_idempotent(email, attrs)
      assert_email_sent(subject: "Test Subject")

      # Second send – pre-check fires, Mailer is never called.
      assert {:ok, _} = Messages.run_send_message_idempotent(email, attrs)
      assert_no_email_sent()
    end

    test "exactly one record exists after any number of duplicate calls" do
      key = "em_one_rec_#{System.unique_integer()}"
      email = test_email()
      attrs = email_attrs(key)

      for _ <- 1..4 do
        assert {:ok, _} = Messages.run_send_message_idempotent(email, attrs)
      end

      assert count_records_for_key(key) == 1
    end

    test "both first and duplicate calls return the email struct" do
      key = "em_ret_#{System.unique_integer()}"
      email = test_email()
      attrs = email_attrs(key)

      {:ok, r1} = Messages.run_send_message_idempotent(email, attrs)
      {:ok, r2} = Messages.run_send_message_idempotent(email, attrs)

      assert r1.subject == "Test Subject"
      assert r2.subject == "Test Subject"
    end
  end

  describe "run_send_message_idempotent/2 - key scoping" do
    test "different keys send independently and each creates its own record" do
      key_a = "em_scope_a_#{System.unique_integer()}"
      key_b = "em_scope_b_#{System.unique_integer()}"
      email = test_email()

      assert {:ok, _} =
               Messages.run_send_message_idempotent(email, email_attrs(key_a))

      assert_email_sent(subject: "Test Subject")

      assert {:ok, _} =
               Messages.run_send_message_idempotent(email, email_attrs(key_b))

      assert_email_sent(subject: "Test Subject")

      assert count_records_for_key(key_a) == 1
      assert count_records_for_key(key_b) == 1
    end

    test "same key with a different template is a separate send" do
      key = "em_tmpl_#{System.unique_integer()}"
      email = test_email()

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 email,
                 email_attrs(key, "booking_confirmation")
               )

      assert_email_sent(subject: "Test Subject")

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 email,
                 email_attrs(key, "event_notification")
               )

      assert_email_sent(subject: "Test Subject")

      # Two separate records because the template differs.
      assert count_records_for_key(key) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # run_send_sms_idempotent/3  (SMS)
  # ---------------------------------------------------------------------------

  describe "run_send_sms_idempotent/3 - first-time send" do
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "sends the SMS and creates exactly one idempotency record" do
      key = "sms_first_#{System.unique_integer()}"

      assert {:ok, %{id: message_id}} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test SMS message.",
                 sms_attrs(key)
               )

      # In test / noop mode FlowRoute returns a fake mdr2-... ID.
      assert is_binary(message_id)
      assert String.starts_with?(message_id, "mdr2-")
      assert count_records_for_key(key) == 1
    end

    test "record contains the correct fields" do
      key = "sms_fields_#{System.unique_integer()}"
      template = "booking_checkin_reminder"

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test.",
                 sms_attrs(key, template)
               )

      record = Ysc.Repo.get_by(MessageIdempotency, idempotency_key: key)
      assert record.message_type == :sms
      assert record.message_template == template
      assert record.phone_number == "12065551234"
    end
  end

  describe "run_send_sms_idempotent/3 - duplicate handling" do
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "second call with the same key returns {:ok, %{id: _}} without re-sending" do
      key = "sms_dup_#{System.unique_integer()}"
      attrs = sms_attrs(key)

      # First send – real (noop) ID.
      assert {:ok, %{id: first_id}} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test.",
                 attrs
               )

      assert String.starts_with?(first_id, "mdr2-")

      # Second send – pre-check fires; sentinel ID returned.
      assert {:ok, %{id: "mdr2-idempotent"}} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test.",
                 attrs
               )
    end

    test "exactly one record exists after any number of duplicate calls" do
      key = "sms_one_rec_#{System.unique_integer()}"
      attrs = sms_attrs(key)

      for _ <- 1..4 do
        assert {:ok, _} =
                 Messages.run_send_sms_idempotent(
                   "12065551234",
                   "[YSC] Test.",
                   attrs
                 )
      end

      assert count_records_for_key(key) == 1
    end

    test "both first and duplicate calls return {:ok, %{id: _}}" do
      key = "sms_ret_#{System.unique_integer()}"
      attrs = sms_attrs(key)

      {:ok, first} =
        Messages.run_send_sms_idempotent("12065551234", "[YSC] Test.", attrs)

      {:ok, second} =
        Messages.run_send_sms_idempotent("12065551234", "[YSC] Test.", attrs)

      assert is_binary(first.id)
      assert is_binary(second.id)
    end
  end

  describe "run_send_sms_idempotent/3 - key scoping" do
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "different keys send independently and each creates its own record" do
      key_a = "sms_scope_a_#{System.unique_integer()}"
      key_b = "sms_scope_b_#{System.unique_integer()}"

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] A.",
                 sms_attrs(key_a)
               )

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] B.",
                 sms_attrs(key_b)
               )

      assert count_records_for_key(key_a) == 1
      assert count_records_for_key(key_b) == 1
    end

    test "same key with a different template is a separate send" do
      key = "sms_tmpl_#{System.unique_integer()}"

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] A.",
                 sms_attrs(key, "booking_checkin_reminder")
               )

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] B.",
                 sms_attrs(key, "phone_verification")
               )

      assert count_records_for_key(key) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-type isolation
  # ---------------------------------------------------------------------------

  describe "message_type isolation" do
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "email and SMS records with the same idempotency key do not conflict" do
      # The DB unique constraint is (message_type, idempotency_key, message_template).
      # Because message_type differs, both sends must succeed and each creates
      # its own record.
      key = "cross_type_#{System.unique_integer()}"
      email = test_email()

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 email,
                 email_attrs(key, "booking_confirmation")
               )

      assert_email_sent(subject: "Test Subject")

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test.",
                 sms_attrs(key, "booking_checkin_reminder")
               )

      assert count_records_for_key(key) == 2
    end

    test "duplicate email send does not block an SMS with the same key" do
      key = "no_cross_block_#{System.unique_integer()}"
      email = test_email()

      # Send email twice with the same key – second send is deduplicated.
      assert {:ok, _} =
               Messages.run_send_message_idempotent(email, email_attrs(key))

      assert_email_sent(subject: "Test Subject")

      assert {:ok, _} =
               Messages.run_send_message_idempotent(email, email_attrs(key))

      assert_no_email_sent()

      # SMS with the same key should still go through (different message_type).
      assert {:ok, %{id: sms_id}} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test.",
                 sms_attrs(key, "booking_checkin_reminder")
               )

      assert String.starts_with?(sms_id, "mdr2-")
    end
  end

  # ---------------------------------------------------------------------------
  # create_message_idempotency/1  (schema / DB constraint tests)
  # ---------------------------------------------------------------------------

  describe "create_message_idempotency/1" do
    setup do
      %{user: user_fixture()}
    end

    test "creates a record with valid attrs", %{user: user} do
      attrs = %{
        user_id: user.id,
        idempotency_key: "schema_key_#{System.unique_integer()}",
        message_template: "test_template",
        message_type: :email
      }

      assert {:ok, %MessageIdempotency{} = record} =
               Messages.create_message_idempotency(attrs)

      assert record.user_id == user.id
      assert record.idempotency_key == attrs.idempotency_key
    end

    test "rejects a duplicate (type, key, template) triplet", %{user: user} do
      key = "schema_dup_#{System.unique_integer()}"

      attrs = %{
        user_id: user.id,
        idempotency_key: key,
        message_template: "test_template",
        message_type: :email
      }

      assert {:ok, _} = Messages.create_message_idempotency(attrs)
      assert {:error, changeset} = Messages.create_message_idempotency(attrs)
      # The changeset error is placed on :message_type (the first field in
      # the unique_constraint declaration).
      assert changeset.errors[:message_type] != nil
    end

    test "allows same key with different message_type", %{user: user} do
      key = "schema_type_#{System.unique_integer()}"

      email_attrs_rec = %{
        user_id: user.id,
        idempotency_key: key,
        message_template: "test_template",
        message_type: :email
      }

      sms_attrs_rec = %{email_attrs_rec | message_type: :sms}

      assert {:ok, _} = Messages.create_message_idempotency(email_attrs_rec)
      assert {:ok, _} = Messages.create_message_idempotency(sms_attrs_rec)
    end

    test "allows same key with different template", %{user: user} do
      key = "schema_tmpl_#{System.unique_integer()}"

      attrs_a = %{
        user_id: user.id,
        idempotency_key: key,
        message_template: "template_a",
        message_type: :email
      }

      attrs_b = %{attrs_a | message_template: "template_b"}

      assert {:ok, _} = Messages.create_message_idempotency(attrs_a)
      assert {:ok, _} = Messages.create_message_idempotency(attrs_b)
    end

    test "requires idempotency_key" do
      assert {:error, %Ecto.Changeset{errors: errors}} =
               Messages.create_message_idempotency(%{
                 message_template: "tmpl",
                 message_type: :email
               })

      assert Keyword.has_key?(errors, :idempotency_key)
    end

    test "requires message_template" do
      assert {:error, %Ecto.Changeset{errors: errors}} =
               Messages.create_message_idempotency(%{
                 idempotency_key: "k",
                 message_type: :email
               })

      assert Keyword.has_key?(errors, :message_template)
    end

    test "requires message_type" do
      assert {:error, %Ecto.Changeset{errors: errors}} =
               Messages.create_message_idempotency(%{
                 idempotency_key: "k",
                 message_template: "tmpl"
               })

      assert Keyword.has_key?(errors, :message_type)
    end
  end

  # ---------------------------------------------------------------------------
  # list_user_messages/2  and  count_user_messages/1
  # ---------------------------------------------------------------------------

  describe "list_user_messages/2" do
    setup do
      %{user: user_fixture()}
    end

    test "returns messages for a user", %{user: user} do
      insert_record(user.id, "lum_k1_#{System.unique_integer()}", "t1")
      insert_record(user.id, "lum_k2_#{System.unique_integer()}", "t2")

      messages = Messages.list_user_messages(user.id)
      assert length(messages) >= 2
    end

    test "respects limit option", %{user: user} do
      for i <- 1..5 do
        insert_record(
          user.id,
          "lum_lim_#{i}_#{System.unique_integer()}",
          "tmpl"
        )
      end

      assert length(Messages.list_user_messages(user.id, limit: 2)) == 2
    end

    test "respects offset option", %{user: user} do
      for i <- 1..5 do
        insert_record(
          user.id,
          "lum_off_#{i}_#{System.unique_integer()}",
          "tmpl"
        )
      end

      all = Messages.list_user_messages(user.id)
      offset = Messages.list_user_messages(user.id, offset: 2)
      assert length(offset) == length(all) - 2
    end
  end

  describe "count_user_messages/1" do
    setup do
      %{user: user_fixture()}
    end

    test "returns the correct count", %{user: user} do
      insert_record(user.id, "cum_k1_#{System.unique_integer()}", "t1")
      insert_record(user.id, "cum_k2_#{System.unique_integer()}", "t2")

      assert Messages.count_user_messages(user.id) >= 2
    end

    test "returns 0 when user has no messages", %{user: user} do
      assert Messages.count_user_messages(user.id) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp insert_record(user_id, key, template) do
    {:ok, record} =
      Messages.create_message_idempotency(%{
        user_id: user_id,
        idempotency_key: key,
        message_template: template,
        message_type: :email
      })

    record
  end
end
