defmodule YscWeb.AdminBookingEntitlementsLive do
  @moduledoc false
  use YscWeb, :admin_live_view

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  import YscWeb.Components.Autocomplete

  alias Ysc.Accounts
  alias Ysc.Bookings.Entitlements

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Outstanding booking benefits")
     |> assign(:active_page, :bookings)
     |> assign(:filter_property, nil)
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

    list = Entitlements.list_outstanding(property: filter_property)

    {:noreply,
     socket
     |> assign(:filter_property, filter_property)
     |> assign(:outstanding_entitlements, list)}
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
        <div>
          <h1 class="text-2xl font-semibold text-zinc-800">
            Outstanding member benefits
          </h1>
          <p class="text-sm text-zinc-500 mt-1">
            Active entitlements not yet used (not consumed, not expired).
          </p>
        </div>

        <div class="rounded-lg border border-zinc-200 p-4 bg-white max-w-4xl">
          <h2 class="text-sm font-semibold text-zinc-800 mb-3">
            Grant new benefit
          </h2>
          <.form
            for={@entitlement_form}
            id="grant-entitlement-form-org"
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

            <div class="grid grid-cols-1 md:grid-cols-2 gap-3 mt-4">
              <.input
                field={@entitlement_form[:benefit_kind]}
                type="select"
                label="Benefit type"
                options={[
                  {"Percent off stay", "percent_off"},
                  {"Free nights (proportional)", "free_nights"},
                  {"Fixed amount off", "fixed_amount_off"}
                ]}
              />
              <.input
                field={@entitlement_form[:property]}
                type="select"
                label="Property"
                options={[
                  {"Any property", ""},
                  {"Lake Tahoe", "tahoe"},
                  {"Clear Lake", "clear_lake"}
                ]}
              />
              <.input
                field={@entitlement_form[:max_guests]}
                type="number"
                label="Max guests (optional)"
              />
              <.input
                field={@entitlement_form[:free_nights]}
                type="number"
                label="Free nights count"
              />
              <.input
                field={@entitlement_form[:percent_off]}
                type="text"
                label="Percent off (e.g. 50)"
              />
              <.input
                field={@entitlement_form[:buyout_max_discount]}
                type="text"
                label="Buyout max discount (USD)"
              />
              <.input
                field={@entitlement_form[:amount_off]}
                type="text"
                label="Fixed amount off (USD)"
              />
              <.input
                field={@entitlement_form[:expires_on]}
                type="date"
                label="Expires (optional)"
              />
            </div>
            <.input
              field={@entitlement_form[:internal_note]}
              type="textarea"
              label="Internal note (optional)"
              class="mt-3 w-full min-h-[4rem] border border-zinc-300 rounded-md px-3 py-2 text-sm"
            />
            <button
              type="submit"
              id="grant-entitlement-submit-org"
              class="mt-4 px-4 py-2 bg-blue-600 text-white rounded font-semibold text-sm hover:bg-blue-700"
            >
              Grant benefit & email member
            </button>
          </.form>
        </div>

        <div class="flex flex-wrap gap-2 items-center">
          <span class="text-sm text-zinc-600">Property:</span>
          <.link
            patch={~p"/admin/bookings/entitlements"}
            class={[
              "px-3 py-1.5 rounded text-sm font-medium",
              if(is_nil(@filter_property),
                do: "bg-zinc-800 text-white",
                else: "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
              )
            ]}
          >
            All
          </.link>
          <.link
            patch={~p"/admin/bookings/entitlements?property=tahoe"}
            class={[
              "px-3 py-1.5 rounded text-sm font-medium",
              if(@filter_property == :tahoe,
                do: "bg-zinc-800 text-white",
                else: "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
              )
            ]}
          >
            Tahoe
          </.link>
          <.link
            patch={~p"/admin/bookings/entitlements?property=clear_lake"}
            class={[
              "px-3 py-1.5 rounded text-sm font-medium",
              if(@filter_property == :clear_lake,
                do: "bg-zinc-800 text-white",
                else: "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
              )
            ]}
          >
            Clear Lake
          </.link>
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
            <tbody class="divide-y divide-zinc-100">
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
                  {benefit_text(ent)}
                </td>
                <td class="px-4 py-3 text-zinc-600">
                  {property_text(ent.property)}
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
          <p
            :if={@outstanding_entitlements == []}
            class="px-4 py-8 text-center text-zinc-500 text-sm"
          >
            No outstanding entitlements for this filter.
          </p>
        </div>
      </div>
    </.side_menu>
    """
  end

  defp entitlement_form do
    to_form(Entitlements.entitlement_grant_default_params(), as: :entitlement)
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{field}: #{Enum.join(messages, ", ")}"
    end)
  end

  defp property_text(nil), do: "Any"
  defp property_text(:tahoe), do: "Tahoe"
  defp property_text(:clear_lake), do: "Clear Lake"

  defp benefit_text(ent) do
    case ent.benefit_kind do
      :free_nights ->
        "#{ent.free_nights} free night(s), max guests #{ent.max_guests || "—"}"

      :percent_off ->
        "#{Decimal.round(ent.percent_off || Decimal.new(0), 0)}% off, buyout cap #{format_m(ent.buyout_max_discount)}"

      :fixed_amount_off ->
        "#{format_m(ent.amount_off)} off"
    end
  end

  defp format_m(nil), do: "—"
  defp format_m(m), do: Ysc.MoneyHelper.format_money!(m)
end
