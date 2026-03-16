defmodule RioWeb.Components.NodeDetailComponent do
  @moduledoc """
  A component for displaying node details in a modal.
  Shows node metadata, status, and action buttons.
  """
  use RioWeb, :live_component

  alias RioWeb.MindMapLive.Helpers
  import RioWeb.Components.SharedComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col min-h-0">
      <%!-- Header: Todo + Title with hover-reveal actions --%>
      <div class="group pb-3 border-b border-base-300">
        <%!-- Action buttons: hidden by default, visible on hover --%>
        <div class="flex items-center gap-0.5 mt-1.5 opacity-0 group-hover:opacity-100 transition-opacity duration-150">
          <.link
            patch={~p"/node/#{@root_id}/edit/#{@node.id}"}
            class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded hover:bg-base-200 transition-colors"
            title="Edit"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-3 w-3"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
              />
            </svg>
            <span>Edit</span>
          </.link>
          <button
            phx-click="focus_subtree"
            phx-value-id={@node.id}
            class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded hover:bg-base-200 transition-colors"
            title="Focus subtree"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-3 w-3"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v3m0 0v3m0-3h3m-3 0H7"
              />
            </svg>
            <span>Focus</span>
          </button>
          <button
            :if={@node.link}
            phx-click="open_node_link"
            phx-value-id={@node.id}
            class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded hover:bg-base-200 transition-colors"
            title="Open link"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-3 w-3"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
              />
            </svg>
            <span>Link</span>
          </button>
          <button
            :if={@node.id != @root_id}
            phx-click="delete_node"
            phx-value-id={@node.id}
            class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded text-error/70 hover:text-error hover:bg-error/10 transition-colors"
            title="Delete"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-3 w-3"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
              />
            </svg>
            <span>Delete</span>
          </button>
        </div>
        <div class="flex items-start gap-2">
          <button
            :if={@node.is_todo}
            phx-click="toggle_todo"
            phx-value-id={@node.id}
            tabindex="-1"
            class="shrink-0 mt-1 flex items-center justify-center cursor-pointer hover:scale-110 transition-transform"
            title={if @node.todo_completed, do: "Mark incomplete", else: "Mark complete"}
          >
            <.todo_checkbox completed={@node.todo_completed} class="w-5 h-5" />
          </button>
          <h3 class={[
            "flex-1 min-w-0 text-lg font-semibold text-base-content leading-tight",
            @node.is_todo && @node.todo_completed && "line-through opacity-60"
          ]}>
            {@node.title}
          </h3>
        </div>
      </div>

      <%!-- Metadata badges below header --%>
      <div
        :if={@node.priority != nil || (@node.is_todo && !@node.todo_completed)}
        class="flex flex-wrap items-center gap-1.5 pt-2"
      >
        <span
          :if={@node.priority != nil}
          class={"badge badge-sm #{priority_badge_color(@node.priority)}"}
        >
          P{@node.priority}
        </span>
        <span :if={@node.is_todo && !@node.todo_completed} class="badge badge-sm badge-warning">
          Pending
        </span>
      </div>

      <%!-- Link (if present) --%>
      <a
        :if={@node.link}
        href={@node.link}
        target="_blank"
        rel="noopener noreferrer"
        class="flex items-center gap-1.5 mt-3 text-xs text-info hover:underline truncate"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="w-3.5 h-3.5 shrink-0"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          stroke-width="2"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"
          />
        </svg>
        <span class="truncate">{@node.link}</span>
      </a>

      <%!-- Body/Notes content --%>
      <div :if={@node.body["content"]} class="mt-4 flex-1 overflow-auto">
        <div class="prose prose-sm max-w-none">
          {RioWeb.Helpers.Markdown.render(@node.body["content"])}
        </div>
      </div>

      <%!-- Empty state for notes --%>
      <div :if={!@node.body["content"]} class="mt-4 flex-1 flex items-center justify-center">
        <p class="text-sm text-base-content/30 italic">No notes yet</p>
      </div>

      <%!-- Footer with metadata --%>
      <div class="mt-4 pt-3 border-t border-base-300 space-y-1.5">
        <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-base-content/50">
          <span :if={@children_count > 0}>
            {@children_count} {if @children_count == 1, do: "child", else: "children"}
          </span>
          <span>
            Created {format_date(@node.inserted_at)}
          </span>
          <span :if={@node.is_todo && @node.completed_at}>
            Completed {format_date(@node.completed_at)}
          </span>
          <span :if={@node.edge_label}>
            Edge: {@node.edge_label}
          </span>
          <span :if={@node.locked}>
            Locked
          </span>
        </div>
      </div>
    </div>
    """
  end

  # Delegate to shared Helpers module
  defp priority_badge_color(priority), do: Helpers.priority_class(priority, :badge)
  defp format_date(datetime), do: Helpers.format_date(datetime)
end
