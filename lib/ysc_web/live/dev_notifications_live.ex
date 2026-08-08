defmodule YscWeb.DevNotificationsLive do
  @moduledoc false
  # Dev-only catalog of email + SMS notification templates with sample data.

  use YscWeb, :live_view

  alias YscWeb.Dev.NotificationSamples

  @impl true
  def mount(_params, _session, socket) do
    emails = NotificationSamples.list_emails()
    sms = NotificationSamples.list_sms()

    {:ok,
     socket
     |> assign(:page_title, "[Dev] Notification previews")
     |> assign(:emails, emails)
     |> assign(:sms_items, sms)
     |> assign(:email_groups, group_emails(emails))
     |> assign(:sms_groups, group_sms(sms))
     |> assign(:tab, :email)
     |> assign(:selected_name, nil)
     |> assign(:selected_kind, nil)
     |> assign(:selected_subject, nil)
     |> assign(:selected_sms_body, nil)
     |> assign(:filter, ""), layout: false}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = parse_tab(params["type"])
    name = params["name"]

    socket =
      socket
      |> assign(:tab, tab)
      |> select_item(tab, name)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, :filter, q || "")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-zinc-100 overflow-hidden">
      <header class="shrink-0 border-b border-zinc-200 bg-white px-4 py-3 flex flex-wrap items-center gap-4 justify-between">
        <div>
          <h1 class="text-lg font-semibold text-zinc-900">Notification previews</h1>
          <p class="text-xs text-zinc-500 mt-0.5">
            Dev-only · sample data from
            <code class="bg-zinc-100 px-1 rounded">{NotificationSamples.samples_path()}</code>
          </p>
        </div>
        <div class="flex items-center gap-3 text-sm">
          <.link
            href="/dev/mailbox"
            class="text-blue-700 hover:underline"
            target="_blank"
          >
            Open mailbox
          </.link>
          <%= if @tab == :email and @selected_name do %>
            <.link
              href={"/dev/preview-email/#{@selected_name}?mailbox=1"}
              class="text-blue-700 hover:underline"
              target="_blank"
            >
              Send to mailbox
            </.link>
            <.link
              href={"/dev/preview-email/#{@selected_name}"}
              class="text-blue-700 hover:underline"
              target="_blank"
            >
              Open HTML
            </.link>
          <% end %>
        </div>
      </header>

      <div class="flex flex-1 min-h-0">
        <aside class="w-80 shrink-0 border-r border-zinc-200 bg-white flex flex-col min-h-0">
          <div class="p-3 border-b border-zinc-100 space-y-3">
            <div class="flex rounded-lg bg-zinc-100 p-1 text-sm font-medium">
              <.link
                patch="/dev/notifications?type=email"
                class={[
                  "flex-1 text-center rounded-md px-2 py-1.5 transition",
                  @tab == :email && "bg-white shadow text-zinc-900",
                  @tab != :email && "text-zinc-600 hover:text-zinc-900"
                ]}
              >
                Emails ({length(@emails)})
              </.link>
              <.link
                patch="/dev/notifications?type=sms"
                class={[
                  "flex-1 text-center rounded-md px-2 py-1.5 transition",
                  @tab == :sms && "bg-white shadow text-zinc-900",
                  @tab != :sms && "text-zinc-600 hover:text-zinc-900"
                ]}
              >
                SMS ({length(@sms_items)})
              </.link>
            </div>
            <form phx-change="filter" id="notification-filter-form">
              <input
                type="search"
                name="q"
                value={@filter}
                placeholder="Filter templates…"
                class="w-full rounded-md border border-zinc-200 px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                id="notification-filter"
              />
            </form>
          </div>

          <nav
            class="flex-1 overflow-y-auto p-2 space-y-4"
            id="notification-sidebar"
          >
            <%= if @tab == :email do %>
              <%= for {category, items} <- filtered_email_groups(@email_groups, @filter) do %>
                <div>
                  <h2 class="px-2 mb-1 text-[11px] font-semibold uppercase tracking-wide text-zinc-400">
                    {category_label(category)}
                  </h2>
                  <ul class="space-y-0.5">
                    <%= for item <- items do %>
                      <li>
                        <.link
                          patch={"/dev/notifications?type=email&name=#{item.name}"}
                          class={[
                            "block rounded-md px-2 py-1.5 text-sm leading-snug",
                            @selected_name == item.name && @tab == :email &&
                              "bg-blue-50 text-blue-900 font-medium",
                            !(@selected_name == item.name && @tab == :email) &&
                              "text-zinc-700 hover:bg-zinc-50"
                          ]}
                          id={"email-nav-#{item.name}"}
                        >
                          <span class="block truncate">{item.name}</span>
                          <span class="block truncate text-xs text-zinc-500 font-normal">
                            {item.subject}
                          </span>
                        </.link>
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            <% else %>
              <%= for {category, items} <- filtered_sms_groups(@sms_groups, @filter) do %>
                <div>
                  <h2 class="px-2 mb-1 text-[11px] font-semibold uppercase tracking-wide text-zinc-400">
                    {category_label(category)}
                  </h2>
                  <ul class="space-y-0.5">
                    <%= for item <- items do %>
                      <li>
                        <.link
                          patch={"/dev/notifications?type=sms&name=#{item.name}"}
                          class={[
                            "block rounded-md px-2 py-1.5 text-sm leading-snug",
                            @selected_name == item.name && @tab == :sms &&
                              "bg-blue-50 text-blue-900 font-medium",
                            !(@selected_name == item.name && @tab == :sms) &&
                              "text-zinc-700 hover:bg-zinc-50"
                          ]}
                          id={"sms-nav-#{item.name}"}
                        >
                          <span class="block truncate">{item.name}</span>
                        </.link>
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            <% end %>
          </nav>
        </aside>

        <main
          class="flex-1 min-w-0 flex flex-col bg-zinc-100"
          id="notification-preview-pane"
        >
          <%= cond do %>
            <% is_nil(@selected_name) -> %>
              <div class="flex-1 flex items-center justify-center text-zinc-500 text-sm">
                Select a template from the sidebar
              </div>
            <% @tab == :email -> %>
              <div class="shrink-0 border-b border-zinc-200 bg-white px-4 py-3">
                <p class="text-xs font-medium text-zinc-500 uppercase tracking-wide">
                  {@selected_name}
                </p>
                <p class="text-sm font-semibold text-zinc-900 mt-0.5">
                  {@selected_subject}
                </p>
              </div>
              <iframe
                src={"/dev/preview-email/#{@selected_name}"}
                title={"Preview #{@selected_name}"}
                class="flex-1 w-full border-0 bg-white"
                id="email-preview-iframe"
              />
            <% true -> %>
              <div class="shrink-0 border-b border-zinc-200 bg-white px-4 py-3">
                <p class="text-xs font-medium text-zinc-500 uppercase tracking-wide">
                  {@selected_name}
                </p>
                <p class="text-sm text-zinc-600 mt-0.5">
                  {String.length(@selected_sms_body || "")} characters
                </p>
              </div>
              <div class="flex-1 overflow-y-auto p-8 flex justify-center items-start">
                <div
                  class="w-full max-w-sm rounded-[2rem] border-8 border-zinc-800 bg-zinc-800 shadow-xl p-3"
                  id="sms-preview-phone"
                >
                  <div class="rounded-2xl bg-zinc-100 px-4 py-3 min-h-[8rem]">
                    <p class="text-[15px] leading-relaxed text-zinc-900 whitespace-pre-wrap">
                      {@selected_sms_body}
                    </p>
                  </div>
                </div>
              </div>
          <% end %>
        </main>
      </div>
    </div>
    """
  end

  defp select_item(socket, :email, name) when is_binary(name) and name != "" do
    case Enum.find(socket.assigns.emails, &(&1.name == name)) do
      nil ->
        assign_empty_selection(socket)

      item ->
        socket
        |> assign(:selected_name, item.name)
        |> assign(:selected_kind, :email)
        |> assign(:selected_subject, item.subject)
        |> assign(:selected_sms_body, nil)
    end
  end

  defp select_item(socket, :sms, name) when is_binary(name) and name != "" do
    case Enum.find(socket.assigns.sms_items, &(&1.name == name)) do
      nil ->
        assign_empty_selection(socket)

      item ->
        body =
          if item.kind == :auto_reply do
            item.body
          else
            case NotificationSamples.render_sms(item.name) do
              {:ok, b} -> b
              _ -> item.body
            end
          end

        socket
        |> assign(:selected_name, item.name)
        |> assign(:selected_kind, :sms)
        |> assign(:selected_subject, nil)
        |> assign(:selected_sms_body, body)
    end
  end

  defp select_item(socket, _tab, _name), do: assign_empty_selection(socket)

  defp assign_empty_selection(socket) do
    socket
    |> assign(:selected_name, nil)
    |> assign(:selected_kind, nil)
    |> assign(:selected_subject, nil)
    |> assign(:selected_sms_body, nil)
  end

  defp parse_tab("sms"), do: :sms
  defp parse_tab(_), do: :email

  defp group_emails(emails) do
    emails
    |> Enum.group_by(& &1.category)
    |> Enum.sort_by(fn {cat, _} -> category_sort(cat) end)
  end

  defp group_sms(items) do
    items
    |> Enum.group_by(& &1.category)
    |> Enum.sort_by(fn {cat, _} -> category_sort(cat) end)
  end

  defp filtered_email_groups(groups, filter) do
    q = String.downcase(String.trim(filter || ""))

    if q == "" do
      groups
    else
      Enum.flat_map(groups, fn {cat, items} ->
        matched =
          Enum.filter(items, fn item ->
            String.contains?(String.downcase(item.name), q) or
              String.contains?(String.downcase(item.subject || ""), q)
          end)

        if matched == [], do: [], else: [{cat, matched}]
      end)
    end
  end

  defp filtered_sms_groups(groups, filter) do
    q = String.downcase(String.trim(filter || ""))

    if q == "" do
      groups
    else
      Enum.flat_map(groups, fn {cat, items} ->
        matched =
          Enum.filter(items, fn item ->
            String.contains?(String.downcase(item.name), q) or
              String.contains?(String.downcase(item.body || ""), q)
          end)

        if matched == [], do: [], else: [{cat, matched}]
      end)
    end
  end

  defp category_label(:account), do: "Account"
  defp category_label(:event), do: "Event"
  defp category_label(:newsletter), do: "Newsletter"
  defp category_label(:auto_reply), do: "Auto-replies"
  defp category_label(other), do: other |> to_string() |> String.capitalize()

  defp category_sort(:account), do: 0
  defp category_sort(:event), do: 1
  defp category_sort(:newsletter), do: 2
  defp category_sort(:auto_reply), do: 3
  defp category_sort(_), do: 9
end
