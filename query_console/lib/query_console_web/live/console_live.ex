defmodule QueryConsoleWeb.ConsoleLive do
  use QueryConsoleWeb, :live_view

  alias QueryConsole.{Catalog, Runner, Workbooks}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    workbooks = Workbooks.list_workbooks(user)

    socket =
      socket
      |> assign(:page_title, "Query Console")
      |> assign(:workbook, nil)
      |> assign(:sql, "")
      |> assign(:run_status, "idle")
      |> assign(:run_detail, nil)
      |> assign(:active_query_run_id, nil)
      |> assign(:results, [])
      |> assign(:active_result_index, 0)
      |> assign(:saving?, false)
      |> stream(:workbooks, workbooks)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    user = socket.assigns.current_user

    case Workbooks.list_workbooks(user) do
      [first | _] ->
        push_patch(socket, to: ~p"/workbooks/#{first.id}")

      [] ->
        case Workbooks.create_workbook(user, %{
               title: "Untitled",
               sql: "-- Write a SELECT query\n"
             }) do
          {:ok, workbook} ->
            socket
            |> stream_insert(:workbooks, workbook, at: 0)
            |> push_patch(to: ~p"/workbooks/#{workbook.id}")

          {:error, _} ->
            put_flash(socket, :error, "Could not create workbook")
        end
    end
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    user = socket.assigns.current_user

    case Workbooks.get_workbook(user, id) do
      {:ok, workbook} ->
        socket
        |> assign(:workbook, workbook)
        |> assign(:sql, workbook.sql)
        |> assign(:page_title, workbook.title)
        |> push_schema()

      {:error, :forbidden} ->
        socket
        |> put_flash(:error, "Workbook not found")
        |> push_navigate(to: ~p"/")

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Workbook not found")
        |> push_navigate(to: ~p"/")
    end
  end

  defp push_schema(socket) do
    if connected?(socket) do
      schema =
        try do
          Catalog.to_codemirror_schema()
        rescue
          _ -> %{}
        catch
          :exit, _ -> %{}
        end

      push_event(socket, "schema", %{schema: schema})
    else
      socket
    end
  end

  @impl true
  def handle_event("new_workbook", _params, socket) do
    user = socket.assigns.current_user

    case Workbooks.create_workbook(user, %{
           title: "Untitled",
           sql: "-- Write a SELECT query\n"
         }) do
      {:ok, workbook} ->
        {:noreply,
         socket
         |> stream_insert(:workbooks, workbook, at: 0)
         |> push_patch(to: ~p"/workbooks/#{workbook.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create workbook")}
    end
  end

  def handle_event("select_workbook", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/workbooks/#{id}")}
  end

  def handle_event("delete_workbook", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Workbooks.delete_workbook(user, id) do
      {:ok, workbook} ->
        socket = stream_delete(socket, :workbooks, workbook)

        socket =
          if socket.assigns.workbook && socket.assigns.workbook.id == id do
            push_navigate(socket, to: ~p"/")
          else
            socket
          end

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete workbook")}
    end
  end

  def handle_event("sql_changed", %{"sql" => sql}, socket) do
    socket = assign(socket, :sql, sql)
    workbook = socket.assigns.workbook

    if workbook do
      socket = assign(socket, :saving?, true)

      case Workbooks.autosave(socket.assigns.current_user, workbook, sql) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign(:workbook, updated)
           |> assign(:saving?, false)
           |> stream_insert(:workbooks, updated)}

        {:error, _} ->
          {:noreply, assign(socket, :saving?, false)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("rename_workbook", %{"title" => title}, socket) do
    user = socket.assigns.current_user
    workbook = socket.assigns.workbook

    case Workbooks.update_workbook(user, workbook, %{title: title}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:workbook, updated)
         |> assign(:page_title, updated.title)
         |> stream_insert(:workbooks, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not rename workbook")}
    end
  end

  def handle_event("run_all", params, socket), do: start_run(socket, "all", params)
  def handle_event("run_current", params, socket), do: start_run(socket, "current", params)
  def handle_event("run_selection", params, socket), do: start_run(socket, "selection", params)

  def handle_event("cancel_run", _params, socket) do
    if id = socket.assigns.active_query_run_id do
      _ = Runner.cancel_run(id)
    end

    {:noreply, assign(socket, :run_status, "cancelling")}
  end

  def handle_event("select_result_tab", %{"index" => index}, socket) do
    index = String.to_integer(index)
    socket = assign(socket, :active_result_index, index)

    socket =
      case Enum.at(socket.assigns.results, index) do
        nil ->
          socket

        result ->
          push_event(socket, "results", %{
            columns: result.columns,
            rows: result.rows,
            truncated: result.truncated?
          })
      end

    {:noreply, socket}
  end

  def handle_event("refresh_schema", _params, socket) do
    _ = Catalog.refresh()
    {:noreply, push_schema(socket)}
  end

  defp start_run(socket, mode, params) do
    user = socket.assigns.current_user
    workbook = socket.assigns.workbook
    sql = Map.get(params, "sql") || socket.assigns.sql

    opts = [
      sql: sql,
      mode: mode,
      caller: self(),
      workbook_id: workbook && workbook.id,
      selection: Map.get(params, "selection"),
      statement_index:
        case Map.get(params, "statement_index") do
          nil -> 0
          idx when is_integer(idx) -> idx
          idx when is_binary(idx) -> String.to_integer(idx)
        end
    ]

    case Runner.start_run(user, opts) do
      {:ok, query_run} ->
        {:noreply,
         socket
         |> assign(:sql, sql)
         |> assign(:run_status, "queued")
         |> assign(:run_detail, nil)
         |> assign(:active_query_run_id, query_run.id)
         |> assign(:results, [])
         |> assign(:active_result_index, 0)}

      {:error, {:write_rejected, message}} ->
        {:noreply,
         socket
         |> assign(:run_status, "failed")
         |> assign(:run_detail, message)
         |> put_flash(:error, message)}

      {:error, {:parse_error, message}} ->
        {:noreply,
         socket
         |> assign(:run_status, "failed")
         |> assign(:run_detail, message)
         |> put_flash(:error, "Parse error: #{message}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:run_status, "failed")
         |> assign(:run_detail, inspect(reason))
         |> put_flash(:error, "Could not start run: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:run_progress, payload}, socket) do
    state = Map.get(payload, :state) || Map.get(payload, "state")

    socket =
      socket
      |> assign(:run_status, state)
      |> assign(:run_detail, format_detail(payload))

    socket =
      if state == "statement_completed" do
        result = %{
          index: payload[:statement_index] || payload["statement_index"],
          columns: payload[:columns] || payload["columns"] || [],
          rows: payload[:result_rows] || payload["result_rows"] || [],
          truncated?: payload[:truncated?] || payload["truncated?"] || false,
          elapsed_ms: payload[:elapsed_ms] || payload["elapsed_ms"],
          rows_count: payload[:rows] || payload["rows"]
        }

        results = socket.assigns.results ++ [result]
        index = length(results) - 1

        socket
        |> assign(:results, results)
        |> assign(:active_result_index, index)
        |> push_event("results", %{
          columns: result.columns,
          rows: result.rows,
          truncated: result.truncated?
        })
      else
        socket
      end

    {:noreply, socket}
  end

  defp format_detail(%{statement_index: idx, statement_total: total, elapsed_ms: ms, rows: rows})
       when is_integer(idx) do
    "Statement #{idx + 1} of #{total} · #{ms || 0}ms · #{rows || 0} rows"
  end

  defp format_detail(%{error: error}) when not is_nil(error), do: to_string(error)
  defp format_detail(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{user: @current_user}}>
      <div id="console" class="flex h-[calc(100vh-4rem)] gap-0 -mx-4 -my-4">
        <aside class="w-64 shrink-0 border-r border-base-300 bg-base-200/50 flex flex-col">
          <div class="p-3 flex items-center justify-between gap-2 border-b border-base-300">
            <span class="font-semibold text-sm">Workbooks</span>
            <button
              id="new-workbook"
              type="button"
              class="btn btn-ghost btn-xs"
              phx-click="new_workbook"
            >
              <.icon name="hero-plus" class="w-4 h-4" />
            </button>
          </div>
          <div id="workbook-list" phx-update="stream" class="flex-1 overflow-y-auto p-2 space-y-1">
            <div
              :for={{dom_id, wb} <- @streams.workbooks}
              id={dom_id}
              class={[
                "group flex items-center gap-1 rounded px-2 py-1.5 text-sm cursor-pointer",
                @workbook && @workbook.id == wb.id && "bg-primary/15 text-primary",
                !(@workbook && @workbook.id == wb.id) && "hover:bg-base-300"
              ]}
              phx-click="select_workbook"
              phx-value-id={wb.id}
            >
              <span class="truncate flex-1">{wb.title}</span>
              <button
                type="button"
                class="btn btn-ghost btn-xs opacity-0 group-hover:opacity-100"
                phx-click="delete_workbook"
                phx-value-id={wb.id}
                data-confirm="Delete this workbook?"
              >
                <.icon name="hero-trash" class="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
          <div class="p-3 border-t border-base-300 text-xs text-base-content/60">
            {@current_user.email}
            <.link href={~p"/auth/logout"} class="ml-2 underline" id="sign-out">
              Sign out
            </.link>
          </div>
        </aside>

        <section class="flex-1 flex flex-col min-w-0">
          <header class="flex items-center gap-2 px-4 py-2 border-b border-base-300">
            <%= if @workbook do %>
              <form phx-submit="rename_workbook" id="rename-form" class="flex-1">
                <input
                  type="text"
                  name="title"
                  value={@workbook.title}
                  class="input input-sm input-ghost w-full max-w-md font-medium"
                  id="workbook-title"
                />
              </form>
            <% end %>
            <span :if={@saving?} class="text-xs text-base-content/50">Saving…</span>
            <button
              id="refresh-schema"
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="refresh_schema"
              title="Refresh schema"
            >
              <.icon name="hero-arrow-path" class="w-4 h-4" />
            </button>
            <button id="run-selection" type="button" class="btn btn-sm" phx-click="run_selection">
              Run selection
            </button>
            <button id="run-current" type="button" class="btn btn-sm" phx-click="run_current">
              Run current
            </button>
            <button id="run-all" type="button" class="btn btn-primary btn-sm" phx-click="run_all">
              Run all
            </button>
            <button
              id="cancel-run"
              type="button"
              class="btn btn-error btn-sm btn-outline"
              phx-click="cancel_run"
              disabled={@run_status in ["idle", "completed", "failed", "cancelled", "timed_out"]}
            >
              Cancel
            </button>
          </header>

          <div
            id="sql-editor"
            phx-hook="SqlEditor"
            phx-update="ignore"
            class="flex-1 min-h-[200px] border-b border-base-300"
            data-sql={@sql}
          >
          </div>

          <div id="run-status" class="px-4 py-1.5 text-xs border-b border-base-300 bg-base-200/40">
            <span class="font-medium uppercase tracking-wide">{@run_status}</span>
            <span :if={@run_detail} class="ml-2 text-base-content/70">{@run_detail}</span>
          </div>

          <div id="results-panel" class="h-72 flex flex-col">
            <div class="flex gap-1 px-2 pt-2 border-b border-base-300">
              <button
                :for={{result, idx} <- Enum.with_index(@results)}
                type="button"
                id={"result-tab-#{idx}"}
                class={[
                  "btn btn-xs",
                  @active_result_index == idx && "btn-active"
                ]}
                phx-click="select_result_tab"
                phx-value-index={idx}
              >
                Result {idx + 1}
                <span class="opacity-60">({result.rows_count || length(result.rows)})</span>
              </button>
              <span :if={@results == []} class="text-xs text-base-content/50 px-2 py-1">
                Results appear here after a successful run
              </span>
            </div>
            <div
              id="results-grid"
              phx-hook="ResultsGrid"
              phx-update="ignore"
              class="flex-1 overflow-hidden"
            >
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
