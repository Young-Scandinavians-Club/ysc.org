defmodule YscWeb.ShopAccess do
  @moduledoc """
  LiveView `on_mount` hooks for the merch shop.

  Anyone may browse the catalog and product pages. Only active members may buy:
  the cart and checkout are gated with `:ensure_member`, and the public pages
  use `:assign_buyer` to learn whether to offer the buy controls. Club admins
  count as members, so they can support members and check the shop. Viewing past
  orders is deliberately not gated here: a lapsed member keeps access to their
  receipts.

  Both run after `YscWeb.UserAuth` has assigned `:current_user` and
  `:active_membership?` (`:ensure_authenticated` or `:mount_current_user`).
  """
  use YscWeb, :verified_routes

  @doc """
  Assigns `:can_buy?`, whether the viewer may add to a cart. Never halts, so
  visitors and non-members can still see the page.
  """
  def on_mount(:assign_buyer, _params, _session, socket) do
    can_buy? =
      member_access?(
        socket.assigns[:current_user],
        socket.assigns[:active_membership?]
      )

    {:cont, Phoenix.Component.assign(socket, :can_buy?, can_buy?)}
  end

  def on_mount(:ensure_member, _params, _session, socket) do
    user = socket.assigns[:current_user]

    if member_access?(user, socket.assigns[:active_membership?]) do
      {:cont, socket}
    else
      socket =
        socket
        |> YscWeb.Flash.put_toast(
          :info,
          "The shop is for active YSC members. Renew your membership to shop.",
          title: "Members only"
        )
        |> Phoenix.LiveView.redirect(to: ~p"/users/membership")

      {:halt, socket}
    end
  end

  @doc """
  Whether the main navigation links to the shop. Off until switched on with
  `SHOP_NAV_VISIBLE=true` (see `config/runtime.exs`); the shop itself stays
  reachable at `/shop` for anyone, signed in or not.
  """
  def nav_visible?, do: Application.get_env(:ysc, :shop_nav_visible, false)

  @doc false
  def member_access?(nil, _active?), do: false
  def member_access?(%{role: :admin}, _active?), do: true
  def member_access?(_user, active?), do: active? == true
end
