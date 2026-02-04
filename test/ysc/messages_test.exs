defmodule Ysc.MessagesTest do
  @moduledoc """
  Tests for Ysc.Messages context module.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Messages
  alias Ysc.Messages.MessageIdempotency
  import Ysc.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "list_user_messages/2" do
    test "returns messages for a user", %{user: user} do
      # Create some messages
      create_message_idempotency(user.id, "key1", "template1")
      create_message_idempotency(user.id, "key2", "template2")

      messages = Messages.list_user_messages(user.id)
      assert length(messages) >= 2
    end

    test "respects limit option", %{user: user} do
      # Create multiple messages
      for i <- 1..5 do
        create_message_idempotency(user.id, "key#{i}", "template#{i}")
      end

      messages = Messages.list_user_messages(user.id, limit: 2)
      assert length(messages) == 2
    end

    test "respects offset option", %{user: user} do
      # Create multiple messages
      for i <- 1..5 do
        create_message_idempotency(user.id, "key#{i}", "template#{i}")
      end

      all_messages = Messages.list_user_messages(user.id)
      offset_messages = Messages.list_user_messages(user.id, offset: 2)

      assert length(offset_messages) == length(all_messages) - 2
    end
  end

  describe "count_user_messages/1" do
    test "returns count of messages for a user", %{user: user} do
      create_message_idempotency(user.id, "key1", "template1")
      create_message_idempotency(user.id, "key2", "template2")

      count = Messages.count_user_messages(user.id)
      assert count >= 2
    end

    test "returns 0 for user with no messages", %{user: user} do
      count = Messages.count_user_messages(user.id)
      assert count == 0
    end
  end

  describe "create_message_idempotency/1" do
    test "creates a message idempotency record", %{user: user} do
      attrs = %{
        user_id: user.id,
        idempotency_key: "test_key_#{System.unique_integer()}",
        message_template: "test_template",
        message_type: :email,
        email_to: "test@example.com"
      }

      assert {:ok, %MessageIdempotency{} = message} =
               Messages.create_message_idempotency(attrs)

      assert message.user_id == user.id
      assert message.idempotency_key == attrs.idempotency_key
    end

    test "requires idempotency_key", %{user: user} do
      attrs = %{
        user_id: user.id,
        message_template: "test_template"
      }

      assert {:error, %Ecto.Changeset{}} =
               Messages.create_message_idempotency(attrs)
    end
  end

  # Helper function
  defp create_message_idempotency(user_id, idempotency_key, message_template) do
    attrs = %{
      user_id: user_id,
      idempotency_key: idempotency_key,
      message_template: message_template,
      message_type: :email,
      email_to: "test@example.com"
    }

    {:ok, message} = Messages.create_message_idempotency(attrs)
    message
  end
end
