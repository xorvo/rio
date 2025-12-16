defmodule WorkTreeWeb.Components.PriorityPickerComponent do
  @moduledoc """
  Quick select menu for setting priority levels on nodes.
  Supports Chinese input method-style number selection (0-3 for priorities, x to clear).
  """
  use WorkTreeWeb, :html

  alias WorkTreeWeb.MindMapLive.Helpers

  @priority_levels [
    {0, "P0 - Critical", "bg-error text-error-content"},
    {1, "P1 - High", "bg-warning text-warning-content"},
    {2, "P2 - Medium", "bg-info text-info-content"},
    {3, "P3 - Low", "bg-success text-success-content"}
  ]

  attr :priority_picker_open, :boolean, required: true
  attr :focused_node, :map, required: true
  attr :selected_node_ids, :any, required: true

  def priority_picker(assigns) do
    assigns = assign(assigns, :priority_levels, @priority_levels)
    assigns = assign(assigns, :batch_mode, MapSet.size(assigns.selected_node_ids) > 0)
    assigns = assign(assigns, :batch_count, MapSet.size(assigns.selected_node_ids))

    ~H"""
    <div
      :if={@priority_picker_open}
      id="priority-picker-backdrop"
      class="priority-picker-backdrop"
      phx-click="close_priority_picker"
      phx-window-keydown="priority_picker_keydown"
    >
      <div
        id="priority-picker"
        class="priority-picker"
        phx-click-away="close_priority_picker"
      >
        <div class="priority-picker-header">
          <%= if @batch_mode do %>
            <span class="flex items-center gap-2">
              Set priority for
              <span class="badge badge-secondary badge-sm"><%= @batch_count %></span>
              nodes
            </span>
          <% else %>
            Set Priority
          <% end %>
        </div>

        <div class="priority-picker-options">
          <%= for {level, label, _color} <- @priority_levels do %>
            <button
              type="button"
              class={[
                "priority-picker-option",
                !@batch_mode && @focused_node && @focused_node.priority == level && "active"
              ]}
              phx-click="priority_picker_select"
              phx-value-priority={level}
            >
              <span class="priority-picker-key"><%= level %></span>
              <span class={["priority-picker-badge", priority_color(level)]}><%= "P#{level}" %></span>
              <span class="priority-picker-label"><%= String.replace(label, ~r/^P\d - /, "") %></span>
              <span
                :if={!@batch_mode && @focused_node && @focused_node.priority == level}
                class="priority-picker-current"
              >
                current
              </span>
            </button>
          <% end %>

          <div class="priority-picker-divider"></div>

          <button
            type="button"
            class="priority-picker-option"
            phx-click="priority_picker_select"
            phx-value-priority="clear"
          >
            <span class="priority-picker-key">x</span>
            <span class="priority-picker-label text-base-content/60">Clear priority</span>
          </button>
        </div>

        <div class="priority-picker-footer">
          <span><span class="kbd kbd-xs">0-3</span> select</span>
          <span><span class="kbd kbd-xs">x</span> clear</span>
          <span><span class="kbd kbd-xs">Esc</span> cancel</span>
        </div>
      </div>
    </div>
    """
  end

  defp priority_color(priority), do: Helpers.priority_class(priority, :bg)
end
