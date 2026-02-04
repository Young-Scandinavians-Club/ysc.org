defmodule Ysc.EmailConfig do
  @moduledoc """
  Centralized email configuration helper.
  Provides access to configurable email addresses.
  """

  @doc """
  Returns the from email address for outgoing emails.
  """
  def from_email do
    Application.get_env(:ysc, :emails)[:from_email] || "noreply@ysc.org"
  end

  @doc """
  Returns the from name for outgoing emails.
  """
  def from_name do
    Application.get_env(:ysc, :emails)[:from_name] || "YSC"
  end

  @doc """
  Returns the general contact email address.
  """
  def contact_email do
    Application.get_env(:ysc, :emails)[:contact_email] || "info@ysc.org"
  end

  @doc """
  Returns the admin email address.
  """
  def admin_email do
    Application.get_env(:ysc, :emails)[:admin_email] || "admin@ysc.org"
  end

  @doc """
  Returns the membership email address.
  """
  def membership_email do
    Application.get_env(:ysc, :emails)[:membership_email] ||
      "membership@ysc.org"
  end

  @doc """
  Returns the board email address.
  """
  def board_email do
    Application.get_env(:ysc, :emails)[:board_email] || "board@ysc.org"
  end

  @doc """
  Returns the volunteer email address.
  """
  def volunteer_email do
    Application.get_env(:ysc, :emails)[:volunteer_email] || "volunteer@ysc.org"
  end

  @doc """
  Returns the Tahoe cabin email address.
  """
  def tahoe_email do
    Application.get_env(:ysc, :emails)[:tahoe_email] || "tahoe@ysc.org"
  end

  @doc """
  Returns the Clear Lake cabin email address.
  """
  def clear_lake_email do
    Application.get_env(:ysc, :emails)[:clear_lake_email] || "cl@ysc.org"
  end
end
