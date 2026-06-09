defmodule YscWeb.Sms.Template do
  @moduledoc """
  Shared helpers for SMS template modules under `YscWeb.Sms.*`.

  Centralizes message normalization, the `[YSC]` prefix, greeting copy, and
  verification-code formatting so individual templates stay focused on content.
  """

  @default_first_name "Valued Member"
  @prefix "[YSC]"

  @doc """
  Collapses extra whitespace in an SMS body.
  """
  def normalize_body(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  @doc """
  Prefixes a message with `[YSC]` when missing, then normalizes whitespace.
  """
  def format(body) when is_binary(body) do
    body
    |> String.trim()
    |> prefix_message()
    |> normalize_body()
  end

  @doc """
  Reads `:first_name` from template variables, falling back to the default greeting.
  """
  def first_name(variables, default \\ @default_first_name)
      when is_map(variables) do
    Map.get(variables, :first_name, default)
  end

  @doc """
  Reads an optional `:first_name` from template variables.
  """
  def optional_first_name(variables) when is_map(variables) do
    Map.get(variables, :first_name)
  end

  @doc """
  Extracts a user's first name for template variables.
  """
  def user_first_name(user) do
    if user, do: user.first_name, else: nil
  end

  @doc """
  Prefixes a message with `Hej <name>!` when a first name is present.
  """
  def greeting(message, first_name) when is_binary(message) do
    if first_name do
      "Hej #{first_name}! #{message}"
    else
      message
    end
  end

  @doc """
  Builds a standard security-notification SMS body for account changes.
  """
  def security_notification_body(first_name, message_body)
      when is_binary(first_name) and is_binary(message_body) do
    format("Hej #{first_name}! #{message_body}")
  end

  @doc """
  Normalizes verification codes to a six-digit string.
  """
  def verification_code(code) when is_binary(code), do: code

  def verification_code(code) when is_integer(code) do
    code
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  @doc """
  Builds the common variable map for code-based verification SMS templates.
  """
  def verification_variables(user, code) do
    %{
      code: verification_code(code),
      first_name: user_first_name(user)
    }
  end

  defp prefix_message(body) do
    if String.starts_with?(body, @prefix) do
      body
    else
      "#{@prefix} #{body}"
    end
  end
end
