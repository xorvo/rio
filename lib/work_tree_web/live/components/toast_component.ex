defmodule WorkTreeWeb.Components.ToastComponent do
  @moduledoc """
  Toast components for deletion confirmation and undo notifications.
  """
  use WorkTreeWeb, :html

  attr :pending_deletion, :map, default: nil

  def delete_confirmation_toast(assigns) do
    ~H"""
    <div
      :if={@pending_deletion}
      class="mind-map-undo-toast"
      phx-mounted={
        JS.transition(
          {"ease-out duration-300", "opacity-0 translate-y-4", "opacity-100 translate-y-0"}
        )
      }
    >
      <span class="flex items-center gap-2">
        <span class="text-warning">⚠</span>
        Delete {@pending_deletion.total_count} nodes?
      </span>
      <div class="flex gap-2">
        <button phx-click="confirm_delete" class="btn btn-sm btn-error">
          Delete
        </button>
        <button phx-click="cancel_delete" class="btn btn-sm btn-ghost">
          Cancel
        </button>
      </div>
    </div>
    """
  end

  attr :deletion_batch, :map, default: nil

  def undo_toast(assigns) do
    ~H"""
    <div
      :if={@deletion_batch}
      class="mind-map-undo-toast"
      phx-mounted={
        JS.transition(
          {"ease-out duration-300", "opacity-0 translate-y-4", "opacity-100 translate-y-0"}
        )
      }
    >
      <span class="flex items-center gap-2">
        <span class="text-error">✕</span>
        Deleted "{@deletion_batch.title}"
        <span
          :if={@deletion_batch.descendant_count && @deletion_batch.descendant_count > 0}
          class="text-base-content/60"
        >
          (+{@deletion_batch.descendant_count} children)
        </span>
      </span>
      <div class="flex gap-2">
        <button phx-click="undo_delete" class="btn btn-sm btn-primary">
          Undo
        </button>
        <button phx-click="dismiss_undo" class="btn btn-sm btn-ghost">
          Dismiss
        </button>
      </div>
    </div>
    """
  end
end
