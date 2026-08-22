defmodule Ysc.Accounts.Email do
  @moduledoc """
  Utilities for email address normalization and validation.

  ## Gmail Normalization

  Gmail (and Googlemail) have special handling for email addresses:
  - Dots (.) in the local part are ignored: `john.doe@gmail.com` = `johndoe@gmail.com`
  - Plus addressing is ignored: `john+test@gmail.com` = `john@gmail.com`
  - `googlemail.com` is the same mailbox as `gmail.com` and is normalized to `gmail.com`

  This module normalizes Gmail addresses to their canonical form to prevent:
  - Multiple signups with the same Gmail address using dots/plus-addressing
  - Parallel accounts via `@googlemail.com` vs `@gmail.com`
  - Potential phishing or abuse attempts
  - Confusion about account ownership

  For all other email providers, only basic trimming and lowercasing is applied.
  """

  @gmail_domains ~w(gmail.com googlemail.com)
  @canonical_gmail_domain "gmail.com"

  @doc """
  Normalizes an email address to its canonical form.

  ## Examples

      iex> Ysc.Accounts.Email.normalize("John.Doe+test@Gmail.com")
      "johndoe@gmail.com"

      iex> Ysc.Accounts.Email.normalize("user+tag@gmail.com")
      "user@gmail.com"

      iex> Ysc.Accounts.Email.normalize("User@Example.com")
      "user@example.com"

      iex> Ysc.Accounts.Email.normalize("  test@example.com  ")
      "test@example.com"

      iex> Ysc.Accounts.Email.normalize("invalid-email")
      "invalid-email"
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> normalize_gmail_if_applicable()
  end

  @doc """
  Checks if an email address is a Gmail address.

  ## Examples

      iex> Ysc.Accounts.Email.gmail?("test@gmail.com")
      true

      iex> Ysc.Accounts.Email.gmail?("test@googlemail.com")
      true

      iex> Ysc.Accounts.Email.gmail?("test@example.com")
      false
  """
  @spec gmail?(String.t()) :: boolean()
  def gmail?(email) when is_binary(email) do
    case email |> String.trim() |> String.downcase() |> String.split("@") do
      [local, domain] when local != "" -> domain in @gmail_domains
      _ -> false
    end
  end

  @doc """
  Returns true when two addresses are the same after normalization.

  Gmail addresses with different dot or plus-tag placements compare equal.

  ## Examples

      iex> Ysc.Accounts.Email.equiv?("eaz.holm@gmail.com", "eazholm@gmail.com")
      true

      iex> Ysc.Accounts.Email.equiv?("user@gmail.com", "user@googlemail.com")
      true

      iex> Ysc.Accounts.Email.equiv?("user@example.com", "user@example.com")
      true

      iex> Ysc.Accounts.Email.equiv?("user@example.com", "other@example.com")
      false
  """
  @spec equiv?(String.t(), String.t()) :: boolean()
  def equiv?(left, right) when is_binary(left) and is_binary(right) do
    normalize(left) == normalize(right)
  end

  @doc """
  Normalizes a list or map set of emails for lookups and filters.
  """
  @spec normalize_set(Enum.t()) :: MapSet.t(String.t())
  def normalize_set(emails) do
    emails
    |> Enum.map(&normalize/1)
    |> MapSet.new()
  end

  # Private functions

  defp normalize_gmail_if_applicable(email) do
    case String.split(email, "@") do
      [local, domain] when domain in @gmail_domains ->
        normalized_local =
          local
          |> remove_dots()
          |> remove_plus_addressing()

        "#{normalized_local}@#{@canonical_gmail_domain}"

      _ ->
        email
    end
  end

  defp remove_dots(local_part) do
    String.replace(local_part, ".", "")
  end

  defp remove_plus_addressing(local_part) do
    case String.split(local_part, "+", parts: 2) do
      [base, _tag] -> base
      [base] -> base
    end
  end
end
