defmodule RioWeb.MindMapLive.DragHandlers do
  @moduledoc """
  Handles drag-to-move operations for mind map nodes.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Rio.MindMaps
  alias RioWeb.MindMapLive.Helpers

  @undo_timeout_ms 15_000

  @doc """
  Starts a drag operation for a node.
  Currently just tracks state - actual drag is handled client-side.
  """
  def start_drag(socket, node_id) do
    node = MindMaps.get_node!(node_id)

    socket
    |> assign(:dragging_node, node)
    |> assign(:drag_target_id, nil)
  end

  @doc """
  Cancels the current drag operation.
  """
  def cancel_drag(socket) do
    clear_drag_state(socket)
  end

  @doc """
  Executes the move operation when drag ends on a valid target.
  """
  def execute_move(socket, node_id, new_parent_id) do
    node = MindMaps.get_node!(node_id)

    cond do
      # Check if node is locked - show confirmation
      node.locked ->
        socket
        |> assign(:pending_move, %{
          node: node,
          new_parent_id: new_parent_id
        })

      # Check for circular move (moving to own descendant)
      is_descendant?(new_parent_id, node) ->
        socket
        |> put_flash(:error, "Cannot move a node to its own descendant")
        |> clear_drag_state()

      # Valid move
      true ->
        do_move(socket, node, new_parent_id)
    end
  end

  @doc """
  Confirms move of a locked node after user confirmation.
  """
  def confirm_move(socket) do
    case socket.assigns[:pending_move] do
      %{node: node, new_parent_id: new_parent_id} ->
        socket
        |> assign(:pending_move, nil)
        |> do_move(node, new_parent_id)

      nil ->
        socket
    end
  end

  @doc """
  Cancels a pending move operation (for locked nodes).
  """
  def cancel_pending_move(socket) do
    socket
    |> assign(:pending_move, nil)
    |> clear_drag_state()
  end

  @doc """
  Undoes the last move operation.
  """
  def undo_move(socket) do
    case socket.assigns[:move_undo_info] do
      %{node_id: node_id, old_parent_id: old_parent_id, old_position: old_position} ->
        node = MindMaps.get_node!(node_id)

        case MindMaps.move_node(node, old_parent_id, old_position) do
          {:ok, _} ->
            # Cancel the timer
            if socket.assigns[:move_undo_timer] do
              Process.cancel_timer(socket.assigns.move_undo_timer)
            end

            socket
            |> assign(:move_undo_info, nil)
            |> assign(:move_undo_timer, nil)
            |> Helpers.reload_tree()
            |> put_flash(:info, "Move undone")

          {:error, _reason} ->
            socket
            |> put_flash(:error, "Failed to undo move")
        end

      nil ->
        socket
    end
  end

  @doc """
  Dismisses the undo toast without undoing.
  """
  def dismiss_undo(socket) do
    if socket.assigns[:move_undo_timer] do
      Process.cancel_timer(socket.assigns.move_undo_timer)
    end

    socket
    |> assign(:move_undo_info, nil)
    |> assign(:move_undo_timer, nil)
  end

  @doc """
  Handles the timer message to clear undo state.
  """
  def handle_clear_move_undo(socket) do
    {:noreply,
     socket
     |> assign(:move_undo_info, nil)
     |> assign(:move_undo_timer, nil)}
  end

  # Private functions

  defp do_move(socket, node, new_parent_id) do
    # Store original position for undo
    old_parent_id = node.parent_id
    old_position = node.position

    # Get the next position in the new parent's children
    new_parent = if new_parent_id, do: MindMaps.get_node!(new_parent_id), else: nil
    new_position = get_next_child_position(new_parent_id)

    case MindMaps.move_node(node, new_parent_id, new_position) do
      {:ok, _moved_node} ->
        # Cancel any existing undo timer
        if socket.assigns[:move_undo_timer] do
          Process.cancel_timer(socket.assigns.move_undo_timer)
        end

        # Set up new undo timer
        timer_ref = Process.send_after(self(), :clear_move_undo, @undo_timeout_ms)

        # Format the move description
        new_parent_title = if new_parent, do: new_parent.title, else: "root"

        socket
        |> clear_drag_state()
        |> assign(:move_undo_info, %{
          node_id: node.id,
          node_title: node.title,
          old_parent_id: old_parent_id,
          old_position: old_position,
          new_parent_title: new_parent_title
        })
        |> assign(:move_undo_timer, timer_ref)
        |> Helpers.reload_tree()

      {:error, reason} ->
        socket
        |> clear_drag_state()
        |> put_flash(:error, "Failed to move node: #{inspect(reason)}")
    end
  end

  defp clear_drag_state(socket) do
    socket
    |> assign(:dragging_node, nil)
    |> assign(:drag_target_id, nil)
  end

  defp is_descendant?(potential_descendant_id, ancestor_node) do
    # Check if potential_descendant_id is in the subtree of ancestor_node
    # Cannot move a node to itself
    if potential_descendant_id == ancestor_node.id do
      true
    else
      descendants = MindMaps.get_subtree(ancestor_node)
      descendant_ids = collect_descendant_ids(descendants)
      potential_descendant_id in descendant_ids
    end
  end

  defp collect_descendant_ids(%{children: children}) do
    Enum.flat_map(children, fn child ->
      [child.id | collect_descendant_ids(child)]
    end)
  end

  defp get_next_child_position(nil) do
    # Root level - count existing root nodes
    0
  end

  defp get_next_child_position(parent_id) do
    parent = MindMaps.get_node!(parent_id)
    children = MindMaps.get_children(parent)
    length(children)
  end
end
