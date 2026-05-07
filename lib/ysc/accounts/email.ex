defmodule Ysc.Accounts.Email do
  @moduledoc """
  Utilities for email address normalization and validation.

  ## Gmail Normalization

  Gmail (and Googlemail) have special handling for email addresses:
  - Dots (.) in the local part are ignored: `john.doe@gmail.com` = `johndoe@gmail.com`
  - Plus addressing is ignored: `john+test@gmail.com` = `john@gmail.com`

  This module normalizes Gmail addresses to their canonical form to prevent:
  - Multiple signups with the same Gmail address using dots/plus-addressing
  - Potential phishing or abuse attempts
  - Confusion about account ownership

  For all other email providers, only basic trimming and lowercasing is applied.
  """

  @gmail_domains ~w(gmail.com googlemail.com)

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
    case String.split(email, "@") do
      [_local, domain] -> domain in @gmail_domains
      _ -> false
    end
  end

  # Private functions

  defp normalize_gmail_if_applicable(email) do
    case String.split(email, "@") do
      [local, domain] when domain in @gmail_domains ->
        normalized_local =
          local
          |> remove_dots()
          |> remove_plus_addressing()

        "#{normalized_local}@#{domain}"

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
