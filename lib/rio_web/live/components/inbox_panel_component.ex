defmodule RioWeb.Components.InboxPanelComponent do
  @moduledoc """
  Collapsible left-side panel for reviewing and placing inbox items.
  """
  use RioWeb, :html

  attr :inbox_open, :boolean, required: true
  attr :inbox_items, :list, required: true
  attr :inbox_count, :integer, required: true

  def inbox_panel(assigns) do
    ~H"""
    <%!-- Backdrop (click to close) --%>
    <div
      :if={@inbox_open}
      class="inbox-backdrop"
      phx-click="toggle_inbox"
    />

    <%!-- Panel --%>
    <div class={["inbox-panel", @inbox_open && "open"]}>
      <%!-- Header --%>
      <div class="inbox-panel-header">
        <div class="flex items-center gap-2">
          <h2 class="text-lg font-semibold">Inbox</h2>
          <span :if={@inbox_count > 0} class="badge badge-primary badge-sm">
            {@inbox_count}
          </span>
        </div>
        <button
          type="button"
          class="btn btn-ghost btn-sm btn-square"
          phx-click="toggle_inbox"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <%!-- Quick capture --%>
      <form phx-submit="inbox_quick_capture" class="inbox-quick-capture">
        <input
          type="text"
          name="title"
          placeholder="Quick capture..."
          class="input input-sm input-bordered flex-1"
          autocomplete="off"
        />
        <button type="submit" class="btn btn-primary btn-sm">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
          </svg>
        </button>
      </form>

      <%!-- Items list --%>
      <div class="inbox-items-list">
        <div :if={@inbox_items == []} class="inbox-empty">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-12 w-12 opacity-20 mx-auto mb-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
          </svg>
          <p class="text-sm opacity-50">No pending items</p>
          <p class="text-xs opacity-30 mt-1">Use the API or quick capture above</p>
        </div>

        <.inbox_item_card
          :for={item <- @inbox_items}
          item={item}
        />
      </div>
    </div>
    """
  end

  attr :item, :any, required: true

  defp inbox_item_card(assigns) do
    ~H"""
    <div
      class="inbox-item-card"
      id={"inbox-item-#{@item.id}"}
      phx-hook="InboxItemDrag"
      data-item-id={@item.id}
    >
      <div class="flex items-start gap-2">
        <%!-- Todo indicator --%>
        <div :if={@item.is_todo} class="mt-0.5">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-info" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </div>

        <div class="flex-1 min-w-0">
          <%!-- Title --%>
          <div class="font-medium text-sm truncate">{@item.title}</div>

          <%!-- Badges row --%>
          <div class="flex items-center gap-1.5 mt-1 flex-wrap">
            <span :if={@item.priority} class={"badge badge-xs #{priority_badge_class(@item.priority)}"}>
              P{@item.priority}
            </span>
            <span class="badge badge-xs badge-ghost">
              {@item.source}
            </span>
            <span :if={@item.expires_at} class="text-xs opacity-50">
              {expires_in_text(@item.expires_at)}
            </span>
          </div>
        </div>
      </div>

      <%!-- Actions --%>
      <div class="inbox-item-actions">
        <button
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="inbox_extend_item"
          phx-value-id={@item.id}
          title="Extend 7 days"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-xs text-error"
          phx-click="inbox_dismiss_item"
          phx-value-id={@item.id}
          title="Dismiss"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  defp priority_badge_class(0), do: "badge-error"
  defp priority_badge_class(1), do: "badge-warning"
  defp priority_badge_class(2), do: "badge-info"
  defp priority_badge_class(3), do: "badge-ghost"
  defp priority_badge_class(_), do: "badge-ghost"

  defp expires_in_text(expires_at) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(expires_at, now)

    cond do
      diff_seconds <= 0 -> "expired"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m left"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h left"
      true -> "#{div(diff_seconds, 86_400)}d left"
    end
  end
end
