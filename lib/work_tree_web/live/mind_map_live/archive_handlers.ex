defmodule WorkTreeWeb.MindMapLive.ArchiveHandlers do
  @moduledoc """
  Archive and undo functionality for mind map nodes.
  Handles single archiving with undo capability.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias WorkTree.MindMaps
  alias WorkTreeWeb.MindMapLive.Helpers

  # Undo timeout in milliseconds (15 seconds)
  @undo_timeout 15_000

  @doc """
  Archives a node with undo capability.
  Shows confirmation dialog if more than 3 nodes would be affected.
  """
  def archive_node_with_undo(socket, node) do
    if node.id == socket.assigns.root.id do
      {:noreply,
       socket
       |> put_flash(:error, "Cannot archive the root node from this view")
       |> assign(:selected_node, nil)}
    else
      # Check total count for confirmation
      descendant_count = MindMaps.count_descendants(node)
      total_count = 1 + descendant_count

      # If more than 3 nodes, show confirmation dialog
      if total_count > 3 and socket.assigns.pending_archive == nil do
        {:noreply,
         socket
         |> assign(:pending_archive, %{node: node, total_count: total_count})}
      else
        do_archive(socket, node)
      end
    end
  end

  @doc """
  Undoes the last archive by restoring the archive batch.
  """
  def undo_archive(socket) do
    case socket.assigns.archive_batch do
      nil ->
        {:noreply, socket}

      %{batch_id: batch_id} = archive_info ->
        # Cancel the timer
        if socket.assigns.archive_undo_timer,
          do: Process.cancel_timer(socket.assigns.archive_undo_timer)

        # Restore all nodes in the archive batch
        {:ok, _count} = MindMaps.restore_archive_batch(batch_id)

        # Focus on the original parent or root
        focus_id = archive_info[:parent_id] || socket.assigns.root.id

        {:noreply,
         socket
         |> Helpers.reload_tree()
         |> assign(:archive_batch, nil)
         |> assign(:archive_undo_timer, nil)
         |> assign(:focused_node_id, focus_id)}
    end
  end

  @doc """
  Dismisses the undo toast without restoring.
  """
  def dismiss_archive_undo(socket) do
    if socket.assigns.archive_undo_timer,
      do: Process.cancel_timer(socket.assigns.archive_undo_timer)

    {:noreply,
     socket
     |> assign(:archive_batch, nil)
     |> assign(:archive_undo_timer, nil)}
  end

  @doc """
  Confirms a pending archive operation.
  """
  def confirm_archive(socket) do
    case socket.assigns.pending_archive do
      %{node: node} when not is_nil(node) ->
        socket = assign(socket, :pending_archive, nil)
        do_archive(socket, node)

      nil ->
        {:noreply, socket}
    end
  end

  @doc """
  Cancels a pending archive operation.
  """
  def cancel_archive(socket) do
    {:noreply, assign(socket, :pending_archive, nil)}
  end

  @doc """
  Handles the :clear_archive_undo message to auto-dismiss undo toast.
  """
  def handle_clear_archive_undo(socket) do
    {:noreply,
     socket
     |> assign(:archive_batch, nil)
     |> assign(:archive_undo_timer, nil)}
  end

  # Private helpers

  defp do_archive(socket, node) do
    # Cancel any existing undo timer
    if socket.assigns.archive_undo_timer,
      do: Process.cancel_timer(socket.assigns.archive_undo_timer)

    # Perform archive
    {:ok, %{batch_id: batch_id, descendant_count: descendant_count}} = MindMaps.archive_node(node)

    # Build archive info for undo
    archive_info = %{
      batch_id: batch_id,
      title: node.title,
      descendant_count: descendant_count,
      parent_id: node.parent_id
    }

    # Reset focused node to parent or root
    new_focus = node.parent_id || socket.assigns.root.id

    # Start timer to clear undo option
    timer_ref = Process.send_after(self(), :clear_archive_undo, @undo_timeout)

    {:noreply,
     socket
     |> Helpers.reload_tree()
     |> assign(:selected_node, nil)
     |> assign(:focused_node_id, new_focus)
     |> assign(:archive_batch, archive_info)
     |> assign(:archive_undo_timer, timer_ref)
     |> assign(:pending_archive, nil)}
  end
end
