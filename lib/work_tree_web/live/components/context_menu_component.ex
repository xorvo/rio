defmodule WorkTreeWeb.Components.ContextMenuComponent do
  @moduledoc """
  A reusable context menu component that can be used throughout the application.

  The menu is positioned absolutely and appears at the cursor position when
  triggered by a right-click event.
  """
  use WorkTreeWeb, :live_component

  alias WorkTreeWeb.MindMapLive.Helpers

  @priority_levels [
    {0, "P0 - Critical", "bg-error text-error-content"},
    {1, "P1 - High", "bg-warning text-warning-content"},
    {2, "P2 - Medium", "bg-info text-info-content"},
    {3, "P3 - Low", "bg-success text-success-content"}
  ]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:priority_submenu_open, false)
     |> assign(:priority_levels, @priority_levels)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:priority_submenu_open, false)
     |> assign(:priority_levels, @priority_levels)}
  end

  @impl true
  def render(assigns) do
    # Check if we're in batch mode (multiple nodes selected)
    assigns = assign(assigns, :batch_mode, MapSet.size(assigns.selected_node_ids) > 0)
    assigns = assign(assigns, :batch_count, MapSet.size(assigns.selected_node_ids))

    ~H"""
    <div
      id={@id}
      class="context-menu"
      style={"left: #{@x}px; top: #{@y}px;"}
      phx-click-away="close_context_menu"
      phx-window-keydown="context_menu_keydown"
      phx-target={@myself}
    >
      <ul class="menu bg-base-200 rounded-box shadow-xl w-56 p-2">
        <%= if @batch_mode do %>
          <%!-- Batch mode header --%>
          <li class="menu-title">
            <span class="flex items-center gap-2">
              <span class="badge badge-secondary badge-sm"><%= @batch_count %></span>
              nodes selected
            </span>
          </li>

          <li class="menu-title mt-2 pt-2 border-t border-base-300">
            <span>Batch Status</span>
          </li>

          <%!-- Batch Make Todo --%>
          <li>
            <button type="button" phx-click="menu_batch_make_todo" phx-target={@myself}>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              Make All Todos
            </button>
          </li>

          <%!-- Batch Remove Todo --%>
          <li>
            <button type="button" phx-click="menu_batch_remove_todo" phx-target={@myself}>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
              Remove All Todos
            </button>
          </li>

          <%!-- Batch Mark Complete --%>
          <li>
            <button type="button" phx-click="menu_batch_mark_complete" phx-target={@myself}>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
              Mark All Complete
            </button>
          </li>

          <%!-- Batch Mark Incomplete --%>
          <li>
            <button type="button" phx-click="menu_batch_mark_incomplete" phx-target={@myself}>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-warning" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              Mark All Incomplete
            </button>
          </li>

          <%!-- Batch Priority Submenu --%>
          <li>
            <details open={@priority_submenu_open}>
              <summary phx-click="toggle_priority_submenu" phx-target={@myself}>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4h13M3 8h9m-9 4h6m4 0l4-4m0 0l4 4m-4-4v12" />
                </svg>
                Set All Priority
              </summary>
              <ul class="bg-base-300 rounded-box">
                <%= for {level, label, _color} <- @priority_levels do %>
                  <li>
                    <button
                      type="button"
                      phx-click="menu_batch_set_priority"
                      phx-value-priority={level}
                      phx-target={@myself}
                    >
                      <span class={["badge badge-xs", priority_color(level)]}><%= "P#{level}" %></span>
                      <%= label %>
                    </button>
                  </li>
                <% end %>
                <li class="border-t border-base-content/10 mt-1 pt-1">
                  <button type="button" phx-click="menu_batch_clear_priority" phx-target={@myself}>
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                    Clear All Priority
                  </button>
                </li>
              </ul>
            </details>
          </li>

          <li class="menu-title mt-2 pt-2 border-t border-base-300">
            <span>Danger</span>
          </li>

          <%!-- Batch Delete --%>
          <li>
            <button type="button" phx-click="menu_batch_delete" phx-target={@myself} class="text-error hover:bg-error hover:text-error-content">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
              Delete <%= @batch_count %> nodes
              <kbd class="kbd kbd-xs ml-auto">Del</kbd>
            </button>
          </li>

          <li class="border-t border-base-300 mt-2 pt-2">
            <button type="button" phx-click="menu_clear_selection" phx-target={@myself} class="text-base-content/60">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
              Clear Selection
            </button>
          </li>
        <% else %>
          <%!-- Single node mode (original menu) --%>
          <%!-- Add Child --%>
          <li>
            <button type="button" phx-click="menu_add_child" phx-target={@myself}>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
              </svg>
              Add Child
              <kbd class="kbd kbd-xs ml-auto">o</kbd>
            </button>
          </li>

          <%!-- Edit Node --%>
          <li>
            <button type="button" phx-click="menu_edit_node" phx-target={@myself}>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
              </svg>
              Edit Details
              <kbd class="kbd kbd-xs ml-auto">Enter</kbd>
            </button>
          </li>

          <li class="menu-title mt-2 pt-2 border-t border-base-300">
            <span>Status</span>
          </li>

          <%!-- Toggle Todo --%>
          <li>
            <button type="button" phx-click="menu_toggle_todo" phx-target={@myself}>
              <%= if @node.is_todo do %>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
                Remove Todo
              <% else %>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                Make Todo
              <% end %>
              <kbd class="kbd kbd-xs ml-auto">t</kbd>
            </button>
          </li>

          <%!-- Toggle Completed (only if todo) --%>
          <li :if={@node.is_todo}>
            <button type="button" phx-click="menu_toggle_completed" phx-target={@myself}>
              <%= if @node.todo_completed do %>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-warning" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                Mark Incomplete
              <% else %>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
                Mark Complete
              <% end %>
            </button>
          </li>

          <%!-- Priority Submenu --%>
          <li>
            <details open={@priority_submenu_open}>
              <summary phx-click="toggle_priority_submenu" phx-target={@myself}>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4h13M3 8h9m-9 4h6m4 0l4-4m0 0l4 4m-4-4v12" />
                </svg>
                Set Priority
                <%= if @node.priority do %>
                  <span class={["badge badge-xs ml-1", priority_color(@node.priority)]}>
                    P<%= @node.priority %>
                  </span>
                <% end %>
              </summary>
              <ul class="bg-base-300 rounded-box">
                <%= for {level, label, _color} <- @priority_levels do %>
                  <li>
                    <button
                      type="button"
                      phx-click="menu_set_priority"
                      phx-value-priority={level}
                      phx-target={@myself}
                      class={[@node.priority == level && "active"]}
                    >
                      <span class={["badge badge-xs", priority_color(level)]}><%= "P#{level}" %></span>
                      <%= label %>
                    </button>
                  </li>
                <% end %>
                <li :if={@node.priority != nil} class="border-t border-base-content/10 mt-1 pt-1">
                  <button type="button" phx-click="menu_clear_priority" phx-target={@myself}>
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                    Clear Priority
                  </button>
                </li>
              </ul>
            </details>
          </li>

          <li class="menu-title mt-2 pt-2 border-t border-base-300">
            <span>Links</span>
          </li>

          <%!-- Add/Edit Link --%>
          <li>
            <button type="button" phx-click="menu_edit_link" phx-target={@myself}>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
              </svg>
              <%= if @node.link, do: "Edit Link", else: "Add Link" %>
              <kbd class="kbd kbd-xs ml-auto">a</kbd>
            </button>
          </li>

          <%!-- Open Link (only if link exists) --%>
          <li :if={@node.link}>
            <button type="button" phx-click="menu_open_link" phx-target={@myself}>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
              </svg>
              Open Link
              <kbd class="kbd kbd-xs ml-auto">g</kbd>
            </button>
          </li>

          <li class="menu-title mt-2 pt-2 border-t border-base-300">
            <span>Navigation</span>
          </li>

          <%!-- Focus Subtree --%>
          <li>
            <button type="button" phx-click="menu_focus_subtree" phx-target={@myself}>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v3m0 0v3m0-3h3m-3 0H7" />
              </svg>
              Focus Subtree
              <kbd class="kbd kbd-xs ml-auto">f</kbd>
            </button>
          </li>

          <li class="menu-title mt-2 pt-2 border-t border-base-300">
            <span>Protection</span>
          </li>

          <%!-- Toggle Lock --%>
          <li>
            <button type="button" phx-click="menu_toggle_lock" phx-target={@myself}>
              <%= if @node.locked do %>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-warning" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z" />
                </svg>
                Unlock Node
              <% else %>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
                Lock Node
              <% end %>
            </button>
          </li>

          <li class="menu-title mt-2 pt-2 border-t border-base-300">
            <span>Danger</span>
          </li>

          <%!-- Delete Node --%>
          <li :if={!@is_root}>
            <button type="button" phx-click="menu_delete_node" phx-target={@myself} class="text-error hover:bg-error hover:text-error-content">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
              Delete
              <kbd class="kbd kbd-xs ml-auto">Del</kbd>
            </button>
          </li>

          <li :if={@is_root}>
            <span class="text-base-content/40 cursor-not-allowed">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
              Delete (root)
            </span>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_priority_submenu", _params, socket) do
    {:noreply, assign(socket, :priority_submenu_open, !socket.assigns.priority_submenu_open)}
  end

  def handle_event("context_menu_keydown", %{"key" => "Escape"}, socket) do
    send(self(), {:close_context_menu, nil})
    {:noreply, socket}
  end

  def handle_event("context_menu_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("close_context_menu", _params, socket) do
    send(self(), {:close_context_menu, nil})
    {:noreply, socket}
  end

  def handle_event("menu_add_child", _params, socket) do
    send(self(), {:context_menu_action, :add_child, socket.assigns.node})
    {:noreply, socket}
  end

  def handle_event("menu_edit_node", _params, socket) do
    send(self(), {:context_menu_action, :edit_node, socket.assigns.node})
    {:noreply, socket}
  end

  def handle_event("menu_toggle_todo", _params, socket) do
    send(self(), {:context_menu_action, :toggle_todo, socket.assigns.node})
    {:noreply, socket}
  end

  def handle_event("menu_toggle_completed", _params, socket) do
    send(self(), {:context_menu_action, :toggle_completed, socket.assigns.node})
    {:noreply, socket}
  end

  def handle_event("menu_set_priority", %{"priority" => priority}, socket) do
    priority = String.to_integer(priority)
    send(self(), {:context_menu_action, :set_priority, socket.assigns.node, priority})
    {:noreply, socket}
  end

  def handle_event("menu_clear_priority", _params, socket) do
    send(self(), {:context_menu_action, :clear_priority, socket.assigns.node})
    {:noreply, socket}
  end

  def handle_event("menu_edit_link", _params, socket) do
    send(self(), {:context_menu_action, :edit_link, socket.assigns.node})
    {:noreply, socket}
  end

  def handle_event("menu_open_link", _params, socket) do
    send(self(), {:context_menu_action, :open_link, socket.assigns.node})
    {:noreply, socket}
  end

  def handle_event("menu_focus_subtree", _params, socket) do
    send(self(), {:context_menu_action, :focus_subtree, socket.assigns.node})
    {:noreply, socket}
  end

  def handle_event("menu_toggle_lock", _params, socket) do
    send(self(), {:context_menu_action, :toggle_lock, socket.assigns.node})
    {:noreply, socket}
  end

  def handle_event("menu_delete_node", _params, socket) do
    send(self(), {:context_menu_action, :delete_node, socket.assigns.node})
    {:noreply, socket}
  end

  # Batch action handlers
  def handle_event("menu_batch_make_todo", _params, socket) do
    send(self(), {:context_menu_action, :batch_make_todo, MapSet.to_list(socket.assigns.selected_node_ids)})
    {:noreply, socket}
  end

  def handle_event("menu_batch_remove_todo", _params, socket) do
    send(self(), {:context_menu_action, :batch_remove_todo, MapSet.to_list(socket.assigns.selected_node_ids)})
    {:noreply, socket}
  end

  def handle_event("menu_batch_mark_complete", _params, socket) do
    send(self(), {:context_menu_action, :batch_mark_complete, MapSet.to_list(socket.assigns.selected_node_ids)})
    {:noreply, socket}
  end

  def handle_event("menu_batch_mark_incomplete", _params, socket) do
    send(self(), {:context_menu_action, :batch_mark_incomplete, MapSet.to_list(socket.assigns.selected_node_ids)})
    {:noreply, socket}
  end

  def handle_event("menu_batch_set_priority", %{"priority" => priority}, socket) do
    priority = String.to_integer(priority)
    send(self(), {:context_menu_action, :batch_set_priority, MapSet.to_list(socket.assigns.selected_node_ids), priority})
    {:noreply, socket}
  end

  def handle_event("menu_batch_clear_priority", _params, socket) do
    send(self(), {:context_menu_action, :batch_clear_priority, MapSet.to_list(socket.assigns.selected_node_ids)})
    {:noreply, socket}
  end

  def handle_event("menu_batch_delete", _params, socket) do
    send(self(), {:context_menu_action, :batch_delete, MapSet.to_list(socket.assigns.selected_node_ids)})
    {:noreply, socket}
  end

  def handle_event("menu_clear_selection", _params, socket) do
    send(self(), {:context_menu_action, :clear_selection})
    {:noreply, socket}
  end

  # Delegate to shared Helpers module
  defp priority_color(priority), do: Helpers.priority_class(priority, :bg)
end
