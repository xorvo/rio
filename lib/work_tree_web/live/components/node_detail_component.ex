defmodule WorkTreeWeb.Components.NodeDetailComponent do
  @moduledoc """
  A component for displaying node details in a modal.
  Shows node metadata, status, and action buttons.
  """
  use WorkTreeWeb, :live_component

  alias WorkTreeWeb.MindMapLive.Helpers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Header with title --%>
      <div>
        <h3 class="text-base font-semibold text-base-content flex items-center gap-2">
          <span
            :if={@node.is_todo}
            class={"text-base #{if @node.todo_completed, do: "text-success", else: "text-base-content/40"}"}
          >
            {if @node.todo_completed, do: "☑", else: "☐"}
          </span>
          {@node.title}
        </h3>
        <p :if={@node.link} class="mt-1 text-xs text-info truncate">
          <a href={@node.link} target="_blank" rel="noopener noreferrer" class="hover:underline flex items-center gap-1">
            <svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
            </svg>
            {@node.link}
          </a>
        </p>
      </div>

      <%!-- Metadata grid --%>
      <div class="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
        <%!-- Priority --%>
        <div class="flex items-center gap-2">
          <span class="text-base-content/50">Priority</span>
          <span :if={@node.priority != nil} class={"badge badge-sm #{priority_badge_color(@node.priority)}"}>
            P{@node.priority}
          </span>
          <span :if={@node.priority == nil} class="text-base-content/30">—</span>
        </div>
        <%!-- Todo status --%>
        <div class="flex items-center gap-2">
          <span class="text-base-content/50">Status</span>
          <button
            :if={@node.is_todo}
            phx-click="toggle_todo"
            phx-value-id={@node.id}
            class={"badge badge-sm cursor-pointer hover:opacity-80 #{if @node.todo_completed, do: "badge-success", else: "badge-warning"}"}
          >
            {if @node.todo_completed, do: "Complete", else: "Pending"}
          </button>
          <span :if={!@node.is_todo} class="text-base-content/30">—</span>
        </div>
        <%!-- Completed date --%>
        <div :if={@node.is_todo && @node.completed_at} class="flex items-center gap-2">
          <span class="text-base-content/50">Completed</span>
          <span class="text-base-content/80">{format_date(@node.completed_at)}</span>
        </div>
        <%!-- Children count --%>
        <div class="flex items-center gap-2">
          <span class="text-base-content/50">Children</span>
          <span class="text-base-content/80">{@children_count}</span>
        </div>
        <%!-- Created date --%>
        <div class="flex items-center gap-2">
          <span class="text-base-content/50">Created</span>
          <span class="text-base-content/80">{format_date(@node.inserted_at)}</span>
        </div>
        <%!-- Edge label if present --%>
        <div :if={@node.edge_label} class="flex items-center gap-2 col-span-2">
          <span class="text-base-content/50">Edge label</span>
          <span class="text-base-content/80">{@node.edge_label}</span>
        </div>
        <%!-- Locked status --%>
        <div :if={@node.locked} class="flex items-center gap-2 col-span-2">
          <span class="text-base-content/50">Locked</span>
          <span class="badge badge-sm badge-neutral">Protected</span>
        </div>
      </div>

      <%!-- Body content if present --%>
      <div :if={@node.body["content"]} class="border-t border-base-300 pt-3">
        <div class="text-xs text-base-content/50 mb-1">Notes</div>
        <p class="text-sm text-base-content/80">{@node.body["content"]}</p>
      </div>

      <%!-- Action button group --%>
      <div class="flex items-center justify-between pt-2 border-t border-base-300">
        <div class="join">
          <.link
            patch={~p"/node/#{@root_id}/edit/#{@node.id}"}
            class="join-item btn btn-sm btn-ghost"
            title="Edit details"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
            </svg>
          </.link>
          <button
            phx-click="focus_subtree"
            phx-value-id={@node.id}
            class="join-item btn btn-sm btn-ghost"
            title="Focus subtree"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v3m0 0v3m0-3h3m-3 0H7" />
            </svg>
          </button>
          <button
            :if={@node.link}
            phx-click="open_node_link"
            phx-value-id={@node.id}
            class="join-item btn btn-sm btn-ghost"
            title="Open link"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
            </svg>
          </button>
        </div>
        <button
          :if={@node.id != @root_id}
          phx-click="delete_node"
          phx-value-id={@node.id}
          class="btn btn-sm btn-ghost"
          title="Delete"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  # Delegate to shared Helpers module
  defp priority_badge_color(priority), do: Helpers.priority_class(priority, :badge)
  defp format_date(datetime), do: Helpers.format_date(datetime)
end
