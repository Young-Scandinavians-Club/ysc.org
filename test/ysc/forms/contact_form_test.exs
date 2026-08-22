defmodule Ysc.Forms.ContactFormTest do
  @moduledoc """
  Tests for ContactForm schema.

  These tests verify:
  - Required field validation (name, email, subject, message)
  - Email format validation
  - Message length validation (min 10 characters)
  - User association
  - Database operations
  """
  use Ysc.DataCase, async: true

  alias Ysc.Forms.ContactForm
  alias Ysc.Repo

  import Ysc.AccountsFixtures

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        subject: "Question about membership",
        message: "I would like to know more about membership options."
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      assert changeset.valid?
      assert changeset.changes.name == "John Doe"
      assert changeset.changes.email == "john@example.com"
      assert changeset.changes.subject == "Question about membership"

      assert changeset.changes.message ==
               "I would like to know more about membership options."
    end

    test "creates valid changeset with user association" do
      user = user_fixture()

      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        subject: "Question",
        message: "This is my question.",
        user_id: user.id
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      assert changeset.valid?
      assert changeset.changes.user_id == user.id
    end

    test "requires name" do
      attrs = %{
        email: "john@example.com",
        subject: "Question",
        message: "This is my question."
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires email" do
      attrs = %{
        name: "John Doe",
        subject: "Question",
        message: "This is my question."
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "requires subject" do
      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        message: "This is my question."
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).subject
    end

    test "requires message" do
      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        subject: "Question"
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).message
    end

    test "validates email format" do
      attrs = %{
        name: "John Doe",
        email: "invalid-email",
        subject: "Question",
        message: "This is my question."
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).email
    end

    test "accepts valid email formats" do
      valid_emails = [
        "simple@example.com",
        "user.name@example.com",
        "user+tag@example.com",
        "user_name@example.co.uk",
        "123@example.com"
      ]

      for email <- valid_emails do
        attrs = %{
          name: "John Doe",
          email: email,
          subject: "Question",
          message: "This is my question."
        }

        changeset = ContactForm.changeset(%ContactForm{}, attrs)

        assert changeset.valid?, "Expected #{email} to be valid"
      end
    end

    test "validates message minimum length" do
      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        subject: "Question",
        message: "Too short"
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      refute changeset.valid?

      assert "should be at least 10 character(s)" in errors_on(changeset).message
    end

    test "accepts message with exactly 10 characters" do
      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        subject: "Question",
        message: "0123456789"
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      assert changeset.valid?
    end

    test "accepts message with more than 10 characters" do
      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        subject: "Question",
        message: "This is a longer message with more than 10 characters."
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      assert changeset.valid?
    end

    test "accepts very long message" do
      long_message = String.duplicate("a", 1000)

      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        subject: "Question",
        message: long_message
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      assert changeset.valid?
    end

    test "allows user_id to be nil (anonymous contact)" do
      attrs = %{
        name: "Anonymous",
        email: "anonymous@example.com",
        subject: "Question",
        message: "This is an anonymous question.",
        user_id: nil
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)

      assert changeset.valid?
    end
  end

  describe "database operations" do
    test "can insert and retrieve contact form" do
      user = user_fixture()

      attrs = %{
        name: "Test User",
        email: "test@example.com",
        subject: "Test Subject",
        message: "This is a test message that is long enough.",
        user_id: user.id
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)
      {:ok, contact_form} = Repo.insert(changeset)

      retrieved = Repo.get(ContactForm, contact_form.id)

      assert retrieved.name == "Test User"
      assert retrieved.email == "test@example.com"
      assert retrieved.subject == "Test Subject"
      assert retrieved.message == "This is a test message that is long enough."
      assert retrieved.user_id == user.id
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can insert contact form without user" do
      attrs = %{
        name: "Anonymous User",
        email: "anonymous@example.com",
        subject: "Anonymous Question",
        message: "This is an anonymous message."
      }

      changeset = ContactForm.changeset(%ContactForm{}, attrs)
      {:ok, contact_form} = Repo.insert(changeset)

      retrieved = Repo.get(ContactForm, contact_form.id)

      assert retrieved.name == "Anonymous User"
      assert retrieved.user_id == nil
    end

    test "allows multiple contact forms with same email" do
      attrs1 = %{
        name: "User One",
        email: "same@example.com",
        subject: "First Question",
        message: "This is the first message."
      }

      attrs2 = %{
        name: "User Two",
        email: "same@example.com",
        subject: "Second Question",
        message: "This is the second message."
      }

      changeset1 = ContactForm.changeset(%ContactForm{}, attrs1)
      {:ok, _form1} = Repo.insert(changeset1)

      changeset2 = ContactForm.changeset(%ContactForm{}, attrs2)
      {:ok, _form2} = Repo.insert(changeset2)

      forms =
        Repo.all(from c in ContactForm, where: c.email == "same@example.com")

      assert length(forms) == 2
    end
  end
end
