defmodule YscWeb.AdminBookingEntitlementsLive do
  @moduledoc false
  use YscWeb, :admin_live_view

  require Ysc.Logging

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  import YscWeb.Components.Autocomplete

  alias Ysc.Accounts
  alias Ysc.Bookings.Entitlements
  alias YscWeb.AdminBookingEntitlementHelpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Outstanding booking benefits")
     |> assign(:active_page, :bookings)
     |> assign(:filter_property, nil)
     |> assign(:outstanding_entitlements, [])
     |> assign(:loading_outstanding_entitlements?, false)
     |> assign(:entitlement_form, entitlement_form())
     |> assign(:grant_user_search, "")
     |> assign(:grant_user_results, [])
     |> assign(:grant_selected_user, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter_property =
      case params["property"] do
        "tahoe" -> :tahoe
        "clear_lake" -> :clear_lake
        _ -> nil
      end

    socket =
      socket
      |> assign(:filter_property, filter_property)
      |> assign(:loading_outstanding_entitlements?, true)

    if connected?(socket) do
      send(self(), {:load_outstanding_entitlements, filter_property})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:load_outstanding_entitlements, filter_property}, socket) do
    list = Entitlements.list_outstanding(property: filter_property)

    {:noreply,
     socket
     |> assign(:outstanding_entitlements, list)
     |> assign(:loading_outstanding_entitlements?, false)}
  end

  @impl true
  def handle_event(
        "search-entitlement-grant-users",
        %{"value" => query},
        socket
      ) do
    results =
      if String.length(query) >= 2 do
        Accounts.search_users(query, limit: 10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:grant_user_search, query)
     |> assign(:grant_user_results, results)}
  end

  def handle_event("select-entitlement-grant-user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    {:noreply,
     socket
     |> assign(:grant_selected_user, user)
     |> assign(:grant_user_search, "")
     |> assign(:grant_user_results, [])}
  end

  def handle_event("clear-entitlement-grant-user", _params, socket) do
    {:noreply,
     socket
     |> assign(:grant_selected_user, nil)
     |> assign(:grant_user_search, "")
     |> assign(:grant_user_results, [])}
  end

  def handle_event("validate_entitlement_form", %{"entitlement" => p}, socket) do
    {:noreply, assign(socket, :entitlement_form, to_form(p, as: :entitlement))}
  end

  def handle_event("grant_booking_entitlement", %{"entitlement" => p}, socket) do
    admin_id = socket.assigns.current_user.id
    attrs = Entitlements.grant_attrs_from_entitlement_form(p, admin_id, nil)

    cond do
      is_nil(attrs.user_id) ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Select a member to receive this benefit.",
           title: "Grant benefit"
         )}

      true ->
        case Entitlements.create_entitlement(attrs) do
          {:ok, _} ->
            list =
              Entitlements.list_outstanding(
                property: socket.assigns.filter_property
              )

            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(
               :info,
               "Benefit granted. Member will receive an email.",
               title: "Grant benefit"
             )
             |> assign(:entitlement_form, entitlement_form())
             |> assign(:grant_selected_user, nil)
             |> assign(:grant_user_search, "")
             |> assign(:grant_user_results, [])
             |> assign(:outstanding_entitlements, list)}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(:error, format_changeset_errors(cs),
               title: "Grant benefit"
             )
             |> assign(:entitlement_form, to_form(cs, as: :entitlement))}

          {:error, reason} ->
            Ysc.Logging.error(
              "Booking entitlement created but post-grant step failed",
              error: inspect(reason),
              extra: %{user_id: attrs.user_id, admin_id: admin_id}
            )

            list =
              Entitlements.list_outstanding(
                property: socket.assigns.filter_property
              )

            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(
               :warning,
               "Benefit granted, but notifying the member failed. The benefit is active; do not retry unless you intended a second grant.",
               title: "Grant benefit"
             )
             |> assign(:entitlement_form, entitlement_form())
             |> assign(:grant_selected_user, nil)
             |> assign(:grant_user_search, "")
             |> assign(:grant_user_results, [])
             |> assign(:outstanding_entitlements, list)}
        end
    end
  end

  def handle_event("revoke_booking_entitlement", %{"id" => id}, socket) do
    case Entitlements.get_entitlement(id) do
      nil ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Entitlement not found.",
           title: "Booking benefits"
         )}

      ent ->
        case Entitlements.revoke_entitlement(ent) do
          {:ok, _} ->
            list =
              Entitlements.list_outstanding(
                property: socket.assigns.filter_property
              )

            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(:info, "Benefit revoked.",
               title: "Booking benefits"
             )
             |> assign(:outstanding_entitlements, list)}

          {:error, _} ->
            {:noreply,
             YscWeb.Flash.put_toast(socket, :error, "Could not revoke.",
               title: "Booking benefits"
             )}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="py-6 space-y-6">
        <.admin_page_title subtitle="Active entitlements not yet used (not consumed, not expired).">
          Outstanding member benefits
        </.admin_page_title>

        <div class="rounded-lg border border-zinc-200 p-4 bg-white max-w-4xl">
          <h2 class="text-sm font-semibold text-zinc-800 mb-3">
            Grant new benefit
          </h2>
          <.form
            for={@entitlement_form}
            id="grant-entitlement-form-org"
            phx-change="validate_entitlement_form"
            phx-submit="grant_booking_entitlement"
          >
            <.autocomplete
              id="entitlement-grant-user-autocomplete"
              label="Member"
              name="entitlement[user_id]"
              search_event="search-entitlement-grant-users"
              select_event="select-entitlement-grant-user"
              clear_event="clear-entitlement-grant-user"
              search_value={@grant_user_search}
              results={@grant_user_results}
              selected={@grant_selected_user}
              display_fn={fn user -> "#{user.first_name} #{user.last_name}" end}
              subtitle_fn={fn user -> user.email end}
              placeholder="Search by name or email..."
              required
            />

            <.admin_grant_entitlement_fields
              form={@entitlement_form}
              fieldset_class="mt-4"
            />
            <.button
              type="submit"
              id="grant-entitlement-submit-org"
              phx-disable-with="Granting..."
              class="mt-4"
            >
              Grant benefit & email member
            </.button>
          </.form>
        </div>

        <div class="flex flex-wrap gap-2 items-center">
          <span class="text-sm text-zinc-600">Property:</span>
          <.admin_toggle_pill
            variant={:dark}
            active={is_nil(@filter_property)}
            patch={~p"/admin/bookings/entitlements"}
          >
            All
          </.admin_toggle_pill>
          <.admin_toggle_pill
            variant={:dark}
            active={@filter_property == :tahoe}
            patch={~p"/admin/bookings/entitlements?property=tahoe"}
          >
            Tahoe
          </.admin_toggle_pill>
          <.admin_toggle_pill
            variant={:dark}
            active={@filter_property == :clear_lake}
            patch={~p"/admin/bookings/entitlements?property=clear_lake"}
          >
            Clear Lake
          </.admin_toggle_pill>
        </div>

        <div class="overflow-x-auto rounded-lg border border-zinc-200">
          <table class="min-w-full text-sm">
            <thead class="bg-zinc-50 text-left text-xs font-semibold text-zinc-600 uppercase">
              <tr>
                <th class="px-4 py-3">Member</th>
                <th class="px-4 py-3">Benefit</th>
                <th class="px-4 py-3">Property</th>
                <th class="px-4 py-3">Granted</th>
                <th class="px-4 py-3">Expires</th>
                <th class="px-4 py-3">Issued by</th>
                <th class="px-4 py-3 text-right">Actions</th>
              </tr>
            </thead>
            <tbody
              :if={@loading_outstanding_entitlements?}
              id="entitlements-org-loading"
              role="status"
              aria-live="polite"
            >
              <.table_rows_skeleton
                rows={5}
                colspan={7}
                label="Loading entitlements…"
                padding_class="px-4 py-3"
              />
            </tbody>
            <tbody
              :if={!@loading_outstanding_entitlements?}
              class="divide-y divide-zinc-100"
            >
              <tr :for={ent <- @outstanding_entitlements} class="hover:bg-zinc-50">
                <td class="px-4 py-3">
                  <.link
                    navigate={~p"/admin/users/#{ent.user_id}/details/bookings"}
                    class="text-blue-600 hover:underline font-medium"
                  >
                    {ent.user.first_name} {ent.user.last_name}
                    <span class="block text-xs text-zinc-500 font-normal">
                      {ent.user.email}
                    </span>
                  </.link>
                </td>
                <td class="px-4 py-3 text-zinc-800">
                  {AdminBookingEntitlementHelpers.benefit_summary(ent, :list)}
                </td>
                <td class="px-4 py-3 text-zinc-600">
                  {AdminBookingEntitlementHelpers.property_label(ent.property)}
                </td>
                <td class="px-4 py-3 text-zinc-600 tabular-nums">
                  {Calendar.strftime(ent.inserted_at, "%Y-%m-%d")}
                </td>
                <td class="px-4 py-3 text-zinc-600 tabular-nums">
                  <%= if ent.expires_at do %>
                    {Calendar.strftime(ent.expires_at, "%Y-%m-%d")}
                  <% else %>
                    —
                  <% end %>
                </td>
                <td class="px-4 py-3 text-zinc-600">
                  <%= if ent.issued_by_user do %>
                    {ent.issued_by_user.email}
                  <% else %>
                    —
                  <% end %>
                </td>
                <td class="px-4 py-3 text-right whitespace-nowrap">
                  <button
                    type="button"
                    id={"revoke-entitlement-org-#{ent.id}"}
                    phx-click="revoke_booking_entitlement"
                    phx-value-id={ent.id}
                    data-confirm="Revoke this benefit? It will no longer apply on new bookings for this member."
                    class="text-red-600 hover:text-red-800 hover:underline text-xs font-semibold"
                  >
                    Revoke
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
          <.admin_table_message
            :if={
              !@loading_outstanding_entitlements? and
                @outstanding_entitlements == []
            }
            id="entitlements-empty"
          >
            No outstanding entitlements for this filter.
          </.admin_table_message>
        </div>
      </div>
    </.side_menu>
    """
  end

  defp entitlement_form do
    to_form(Entitlements.entitlement_grant_default_params(), as: :entitlement)
  end

  defp format_changeset_errors(changeset) do
    YscWeb.FormHelpers.format_changeset_errors(changeset)
  end
end
