defmodule YscWeb.ShopAccess do
  @moduledoc """
  LiveView `on_mount` gate for buying from the merch shop.

  Only active members may browse and buy. Club admins are let in too, so they
  can support members and check the shop. Viewing past orders is deliberately
  not gated here: a lapsed member keeps access to their receipts.

  Runs after `YscWeb.UserAuth`'s `:ensure_authenticated`, which assigns
  `:current_user` and `:active_membership?`.
  """
  use YscWeb, :verified_routes

  def on_mount(:ensure_member, _params, _session, socket) do
    user = socket.assigns[:current_user]

    if member_access?(user, socket.assigns[:active_membership?]) do
      {:cont, socket}
    else
      socket =
        socket
        |> YscWeb.Flash.put_toast(
          :info,
          "The merch shop is for active YSC members. Renew your membership to shop.",
          title: "Members only"
        )
        |> Phoenix.LiveView.redirect(to: ~p"/users/membership")

      {:halt, socket}
    end
  end

  @doc false
  def member_access?(nil, _active?), do: false
  def member_access?(%{role: :admin}, _active?), do: true
  def member_access?(_user, active?), do: active? == true
end
