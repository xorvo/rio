defmodule WorkTreeWeb.MindMapLive.DeletionHandlers do
  @moduledoc """
  Deletion and undo functionality for mind map nodes.
  Handles single and batch deletion with soft delete and undo capability.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias WorkTree.MindMaps
  alias WorkTreeWeb.MindMapLive.Helpers

  # Undo timeout in milliseconds
  @undo_timeout 5000

  @doc """
  Deletes a node with undo capability.
  Shows confirmation dialog if more than 3 nodes would be deleted.
  """
  def delete_node_with_undo(socket, node) do
    if node.id == socket.assigns.root.id do
      {:noreply,
       socket
       |> put_flash(:error, "Cannot delete the root node from this view")
       |> assign(:selected_node, nil)}
    else
      # Check total count for confirmation
      descendant_count = MindMaps.count_descendants(node)
      total_count = 1 + descendant_count

      # If more than 3 nodes, show confirmation dialog
      if total_count > 3 and socket.assigns.pending_deletion == nil do
        {:noreply,
         socket
         |> assign(:pending_deletion, %{node_ids: [node.id], total_count: total_count, single_node: node})}
      else
        do_single_delete(socket, node)
      end
    end
  end

  @doc """
  Undoes the last deletion by restoring the deletion batch.
  """
  def undo_delete(socket) do
    case socket.assigns.deletion_batch do
      nil ->
        {:noreply, socket}

      %{batch_id: batch_id} = deletion_info ->
        # Cancel the timer
        if socket.assigns.undo_timer, do: Process.cancel_timer(socket.assigns.undo_timer)

        # Restore all nodes in the deletion batch
        {:ok, _count} = MindMaps.restore_deletion_batch(batch_id)

        # Focus on the original parent or root
        focus_id = deletion_info[:parent_id] || socket.assigns.root.id

        {:noreply,
         socket
         |> Helpers.reload_tree()
         |> assign(:deletion_batch, nil)
         |> assign(:undo_timer, nil)
         |> assign(:focused_node_id, focus_id)}
    end
  end

  @doc """
  Dismisses the undo toast without restoring.
  """
  def dismiss_undo(socket) do
    if socket.assigns.undo_timer, do: Process.cancel_timer(socket.assigns.undo_timer)

    {:noreply,
     socket
     |> assign(:deletion_batch, nil)
     |> assign(:undo_timer, nil)}
  end

  @doc """
  Confirms a pending deletion operation.
  """
  def confirm_delete(socket) do
    case socket.assigns.pending_deletion do
      %{single_node: node} when not is_nil(node) ->
        socket = assign(socket, :pending_deletion, nil)
        do_single_delete(socket, node)

      %{node_ids: node_ids} ->
        socket = assign(socket, :pending_deletion, nil)
        do_batch_delete(socket, node_ids, socket.assigns.root.id)

      nil ->
        {:noreply, socket}
    end
  end

  @doc """
  Cancels a pending deletion operation.
  """
  def cancel_delete(socket) do
    {:noreply, assign(socket, :pending_deletion, nil)}
  end

  @doc """
  Deletes multiple nodes with undo capability.
  Shows confirmation dialog if more than 3 nodes would be deleted.
  """
  def batch_delete_nodes(socket, node_ids) do
    root_id = socket.assigns.root.id

    # Filter out root node from deletion
    deletable_ids = Enum.reject(node_ids, &(&1 == root_id))

    if deletable_ids == [] do
      {:noreply, put_flash(socket, :error, "Cannot delete the root node")}
    else
      # Count total nodes including descendants
      total_count = count_nodes_for_deletion(deletable_ids)

      # If more than 3 nodes, show confirmation dialog
      if total_count > 3 and not socket.assigns[:pending_deletion_confirmed] do
        {:noreply,
         socket
         |> assign(:pending_deletion, %{node_ids: deletable_ids, total_count: total_count})}
      else
        do_batch_delete(socket, deletable_ids, root_id)
      end
    end
  end

  @doc """
  Handles the :clear_undo message to auto-dismiss undo toast.
  """
  def handle_clear_undo(socket) do
    {:noreply,
     socket
     |> assign(:deletion_batch, nil)
     |> assign(:undo_timer, nil)}
  end

  # Private helpers

  defp do_single_delete(socket, node) do
    # Cancel any existing undo timer
    if socket.assigns.undo_timer, do: Process.cancel_timer(socket.assigns.undo_timer)

    # Perform soft delete
    case MindMaps.soft_delete_node(node) do
      {:error, :locked, locked_nodes} ->
        locked_titles = Enum.map_join(locked_nodes, ", ", & &1.title)

        {:noreply,
         socket
         |> put_flash(:error, "Cannot delete: locked nodes found (#{locked_titles})")
         |> assign(:selected_node, nil)
         |> assign(:pending_deletion, nil)}

      {:ok, %{batch_id: batch_id, descendant_count: descendant_count}} ->
        # Build deletion info for undo
        deletion_info = %{
          batch_id: batch_id,
          title: node.title,
          descendant_count: descendant_count,
          parent_id: node.parent_id
        }

        # Reset focused node to parent or root
        new_focus = node.parent_id || socket.assigns.root.id

        # Start timer to clear undo option
        timer_ref = Process.send_after(self(), :clear_undo, @undo_timeout)

        {:noreply,
         socket
         |> Helpers.reload_tree()
         |> assign(:selected_node, nil)
         |> assign(:focused_node_id, new_focus)
         |> assign(:deletion_batch, deletion_info)
         |> assign(:undo_timer, timer_ref)
         |> assign(:pending_deletion, nil)}
    end
  end

  defp do_batch_delete(socket, deletable_ids, root_id) do
    # Cancel any existing undo timer
    if socket.assigns.undo_timer, do: Process.cancel_timer(socket.assigns.undo_timer)

    # Perform soft delete of all selected nodes
    case MindMaps.soft_delete_nodes(deletable_ids) do
      {:error, :locked, locked_nodes} ->
        locked_titles = Enum.map_join(locked_nodes, ", ", & &1.title)

        {:noreply,
         socket
         |> put_flash(:error, "Cannot delete: locked nodes found (#{locked_titles})")
         |> assign(:selected_node_ids, MapSet.new())
         |> assign(:pending_deletion, nil)}

      {:ok, %{batch_id: batch_id, total_count: total_count}} ->
        # Build deletion info for undo
        deletion_info = %{
          batch_id: batch_id,
          title: "#{length(deletable_ids)} nodes",
          descendant_count: total_count - length(deletable_ids),
          parent_id: nil,
          batch: true
        }

        timer_ref = Process.send_after(self(), :clear_undo, @undo_timeout)

        {:noreply,
         socket
         |> Helpers.reload_tree()
         |> assign(:selected_node, nil)
         |> assign(:selected_node_ids, MapSet.new())
         |> assign(:focused_node_id, root_id)
         |> assign(:deletion_batch, deletion_info)
         |> assign(:undo_timer, timer_ref)
         |> assign(:pending_deletion, nil)}
    end
  end

  defp count_nodes_for_deletion(node_ids) do
    Enum.reduce(node_ids, 0, fn id, acc ->
      node = MindMaps.get_node!(id)
      descendant_count = MindMaps.count_descendants(node)
      acc + 1 + descendant_count
    end)
  end
end
