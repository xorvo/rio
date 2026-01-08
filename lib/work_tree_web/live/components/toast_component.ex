defmodule WorkTreeWeb.Components.ToastComponent do
  @moduledoc """
  Toast components for deletion, archive, and move confirmation and undo notifications.
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
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-5 w-5 text-warning"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
          />
        </svg>
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
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-5 w-5 text-error"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
          />
        </svg>
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

  attr :move_undo_info, :map, default: nil

  def move_undo_toast(assigns) do
    ~H"""
    <div
      :if={@move_undo_info}
      class="mind-map-undo-toast"
      phx-mounted={
        JS.transition(
          {"ease-out duration-300", "opacity-0 translate-y-4", "opacity-100 translate-y-0"}
        )
      }
    >
      <span class="flex items-center gap-2">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-5 w-5 text-success"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"
          />
        </svg>
        Moved "{@move_undo_info.node_title}" to "{@move_undo_info.new_parent_title}"
      </span>
      <div class="flex gap-2">
        <button phx-click="undo_move" class="btn btn-sm btn-primary">
          Undo
        </button>
        <button phx-click="dismiss_move_undo" class="btn btn-sm btn-ghost">
          Dismiss
        </button>
      </div>
    </div>
    """
  end

  attr :pending_archive, :map, default: nil

  def archive_confirmation_toast(assigns) do
    ~H"""
    <div
      :if={@pending_archive}
      class="mind-map-undo-toast"
      phx-mounted={
        JS.transition(
          {"ease-out duration-300", "opacity-0 translate-y-4", "opacity-100 translate-y-0"}
        )
      }
    >
      <span class="flex items-center gap-2">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-5 w-5 text-warning"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"
          />
        </svg>
        Archive {@pending_archive.total_count} nodes?
      </span>
      <div class="flex gap-2">
        <button phx-click="confirm_archive" class="btn btn-sm btn-warning">
          Archive
        </button>
        <button phx-click="cancel_archive" class="btn btn-sm btn-ghost">
          Cancel
        </button>
      </div>
    </div>
    """
  end

  attr :archive_batch, :map, default: nil

  def archive_undo_toast(assigns) do
    ~H"""
    <div
      :if={@archive_batch}
      class="mind-map-undo-toast"
      phx-mounted={
        JS.transition(
          {"ease-out duration-300", "opacity-0 translate-y-4", "opacity-100 translate-y-0"}
        )
      }
    >
      <span class="flex items-center gap-2">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-5 w-5 text-info"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"
          />
        </svg>
        Archived "{@archive_batch.title}"
        <span
          :if={@archive_batch.descendant_count && @archive_batch.descendant_count > 0}
          class="text-base-content/60"
        >
          (+{@archive_batch.descendant_count} children)
        </span>
      </span>
      <div class="flex gap-2">
        <button phx-click="undo_archive" class="btn btn-sm btn-primary">
          Undo
        </button>
        <button phx-click="dismiss_archive_undo" class="btn btn-sm btn-ghost">
          Dismiss
        </button>
      </div>
    </div>
    """
  end

  attr :pending_move, :map, default: nil

  def move_confirmation_modal(assigns) do
    ~H"""
    <div
      :if={@pending_move}
      class="modal modal-open"
      phx-mounted={JS.transition({"ease-out duration-200", "opacity-0", "opacity-100"})}
    >
      <div class="modal-box">
        <h3 class="font-bold text-lg flex items-center gap-2">
          <span class="text-warning">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-6 w-6"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
              />
            </svg>
          </span>
          Move Locked Node?
        </h3>
        <p class="py-4">
          The node "<strong>{@pending_move.node.title}</strong>" is locked.
          Are you sure you want to move it?
        </p>
        <div class="modal-action">
          <button phx-click="cancel_move" class="btn btn-ghost">
            Cancel
          </button>
          <button phx-click="confirm_move" class="btn btn-warning">
            Move Anyway
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="cancel_move"></div>
    </div>
    """
  end
end
