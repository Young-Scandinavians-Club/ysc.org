defmodule Ysc.Accounts.EmailTest do
  use ExUnit.Case, async: true

  alias Ysc.Accounts.Email

  doctest Ysc.Accounts.Email

  describe "normalize/1" do
    test "normalizes Gmail addresses by removing dots from local part" do
      assert Email.normalize("john.doe@gmail.com") == "johndoe@gmail.com"
      assert Email.normalize("j.o.h.n@gmail.com") == "john@gmail.com"

      assert Email.normalize("first.middle.last@gmail.com") ==
               "firstmiddlelast@gmail.com"
    end

    test "normalizes Gmail addresses by removing plus-addressing" do
      assert Email.normalize("john+test@gmail.com") == "john@gmail.com"
      assert Email.normalize("john+newsletters@gmail.com") == "john@gmail.com"
      assert Email.normalize("user+tag+more@gmail.com") == "user@gmail.com"
    end

    test "normalizes Gmail addresses by removing both dots and plus-addressing" do
      assert Email.normalize("john.doe+test@gmail.com") == "johndoe@gmail.com"

      assert Email.normalize("first.last+work@gmail.com") ==
               "firstlast@gmail.com"

      assert Email.normalize("j.doe+personal+tag@gmail.com") == "jdoe@gmail.com"
    end

    test "normalizes Googlemail addresses the same as Gmail" do
      assert Email.normalize("john.doe@googlemail.com") ==
               "johndoe@googlemail.com"

      assert Email.normalize("john+test@googlemail.com") ==
               "john@googlemail.com"

      assert Email.normalize("john.doe+test@googlemail.com") ==
               "johndoe@googlemail.com"
    end

    test "handles case insensitivity for Gmail" do
      assert Email.normalize("John.Doe@Gmail.com") == "johndoe@gmail.com"
      assert Email.normalize("JOHN+TEST@GMAIL.COM") == "john@gmail.com"
      assert Email.normalize("JoHn.DoE+TeSt@GmAiL.cOm") == "johndoe@gmail.com"
    end

    test "only lowercases non-Gmail addresses without removing dots or plus" do
      assert Email.normalize("john.doe@example.com") == "john.doe@example.com"
      assert Email.normalize("user+tag@yahoo.com") == "user+tag@yahoo.com"

      assert Email.normalize("Test.User+Work@Outlook.com") ==
               "test.user+work@outlook.com"
    end

    test "trims whitespace from all emails" do
      assert Email.normalize("  test@gmail.com  ") == "test@gmail.com"
      assert Email.normalize("  test@example.com  ") == "test@example.com"
      assert Email.normalize("\tuser@gmail.com\n") == "user@gmail.com"
    end

    test "handles edge cases" do
      assert Email.normalize("") == ""
      assert Email.normalize("invalid-email") == "invalid-email"
      assert Email.normalize("@gmail.com") == "@gmail.com"
      assert Email.normalize("user@") == "user@"
    end

    test "preserves valid email structure" do
      assert Email.normalize("simple@example.com") == "simple@example.com"
      assert Email.normalize("user123@test.org") == "user123@test.org"
      assert Email.normalize("admin@company.co.uk") == "admin@company.co.uk"
    end
  end

  describe "gmail?/1" do
    test "returns true for gmail.com addresses" do
      assert Email.gmail?("test@gmail.com")
      assert Email.gmail?("user@gmail.com")
      assert Email.gmail?("anything@gmail.com")
    end

    test "returns true for googlemail.com addresses" do
      assert Email.gmail?("test@googlemail.com")
      assert Email.gmail?("user@googlemail.com")
    end

    test "returns false for non-Gmail addresses" do
      refute Email.gmail?("test@example.com")
      refute Email.gmail?("user@yahoo.com")
      refute Email.gmail?("admin@outlook.com")
      refute Email.gmail?("support@gmail.org")
    end

    test "returns false for invalid emails" do
      refute Email.gmail?("invalid-email")
      refute Email.gmail?("@gmail.com")
      refute Email.gmail?("")
    end

    test "is case insensitive" do
      assert Email.gmail?("test@GMAIL.COM")
      assert Email.gmail?("test@Gmail.com")
      assert Email.gmail?("test@GmAiL.cOm")
    end
  end
end
