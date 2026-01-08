defmodule WorkTreeWeb.Components.DueDatePickerComponent do
  @moduledoc """
  Quick select menu for setting due dates on nodes.
  Supports number key selection (1-6 for presets, x to clear).
  """
  use WorkTreeWeb, :html

  @due_date_options [
    {1, "immediate", "Immediate", "End of today"},
    {2, "short", "Short", "+7 days"},
    {3, "mid", "Mid", "+14 days"},
    {4, "long", "Long", "+1 month"},
    {5, "longlong", "Long Long", "+2 months"},
    {6, "custom", "Custom", "Pick a date"}
  ]

  attr :due_date_picker_open, :boolean, required: true
  attr :focused_node, :map, required: true
  attr :selected_node_ids, :any, required: true
  attr :custom_date_mode, :boolean, default: false

  def due_date_picker(assigns) do
    assigns = assign(assigns, :due_date_options, @due_date_options)
    assigns = assign(assigns, :batch_mode, MapSet.size(assigns.selected_node_ids) > 0)
    assigns = assign(assigns, :batch_count, MapSet.size(assigns.selected_node_ids))

    ~H"""
    <div
      :if={@due_date_picker_open}
      id="due-date-picker-backdrop"
      class="due-date-picker-backdrop"
      phx-click="close_due_date_picker"
      phx-window-keydown="due_date_picker_keydown"
    >
      <div
        id="due-date-picker"
        class="due-date-picker"
        phx-click-away="close_due_date_picker"
        onclick="event.stopPropagation()"
      >
        <div class="due-date-picker-header">
          <%= if @batch_mode do %>
            <span class="flex items-center gap-2">
              Set due date for <span class="badge badge-secondary badge-sm">{@batch_count}</span>
              nodes
            </span>
          <% else %>
            Set Due Date
          <% end %>
        </div>

        <%= if @custom_date_mode do %>
          <div class="due-date-picker-custom">
            <form phx-submit="due_date_custom_submit" class="flex flex-col gap-2 p-3">
              <input
                type="date"
                name="custom_date"
                id="custom-date-input"
                class="input input-bordered input-sm w-full"
                autofocus
              />
              <div class="flex gap-2">
                <button type="submit" class="btn btn-primary btn-sm flex-1">
                  Set Date
                </button>
                <button type="button" phx-click="due_date_cancel_custom" class="btn btn-ghost btn-sm">
                  Back
                </button>
              </div>
            </form>
          </div>
        <% else %>
          <div class="due-date-picker-options">
            <%= for {key, _id, label, description} <- @due_date_options do %>
              <button
                type="button"
                class="due-date-picker-option"
                phx-click="due_date_picker_select"
                phx-value-option={key}
              >
                <span class="due-date-picker-key">{key}</span>
                <span class="due-date-picker-label">{label}</span>
                <span class="due-date-picker-description">{description}</span>
              </button>
            <% end %>

            <div class="due-date-picker-divider"></div>

            <button
              type="button"
              class="due-date-picker-option"
              phx-click="due_date_picker_select"
              phx-value-option="clear"
            >
              <span class="due-date-picker-key">x</span>
              <span class="due-date-picker-label text-base-content/60">Clear due date</span>
            </button>
          </div>
        <% end %>

        <div class="due-date-picker-footer">
          <span><span class="kbd kbd-xs">1-6</span> select</span>
          <span><span class="kbd kbd-xs">x</span> clear</span>
          <span><span class="kbd kbd-xs">Esc</span> cancel</span>
        </div>
      </div>
    </div>
    """
  end
end
