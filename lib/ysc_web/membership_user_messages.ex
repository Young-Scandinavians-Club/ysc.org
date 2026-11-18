defmodule YscWeb.MembershipUserMessages do
  @moduledoc false

  def payment_method_saved_membership_activated(returning_member?)
      when is_boolean(returning_member?) do
    if returning_member? do
      "Payment method saved. Your membership is renewed."
    else
      "Payment method saved and your membership is now active!"
    end
  end

  def membership_activated_welcome(returning_member?)
      when is_boolean(returning_member?) do
    if returning_member? do
      "Your membership is renewed."
    else
      "Your membership is active. Welcome!"
    end
  end

  def membership_activated_short(returning_member?)
      when is_boolean(returning_member?) do
    if returning_member? do
      "Your membership is renewed."
    else
      "Your membership is active!"
    end
  end
end
