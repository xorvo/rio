defmodule MindMapperPocWeb.MindMapLive.Show do
  use MindMapperPocWeb, :live_view

  alias MindMapperPoc.MindMaps
  alias MindMapperPoc.MindMaps.Layout

  # Undo timeout in milliseconds
  @undo_timeout 5000

  @impl true
  def mount(params, _session, socket) do
    root = get_root_node(params)
    tree = MindMaps.get_subtree(root)
    node_positions = Layout.calculate_positions(tree)
    edges = Layout.calculate_edges(tree, node_positions)
    nodes = Layout.flatten_tree(tree)
    {_min_x, _min_y, max_x, max_y} = Layout.bounding_box(node_positions)

    {:ok,
     socket
     |> assign(:root, root)
     |> assign(:tree, tree)
     |> assign(:node_positions, node_positions)
     |> assign(:edges, edges)
     |> assign(:nodes, nodes)
     |> assign(:canvas_width, max_x + 100)
     |> assign(:canvas_height, max_y + 100)
     |> assign(:focused_node_id, root.id)
     |> assign(:selected_node, nil)
     |> assign(:ancestors, MindMaps.get_ancestors(root))
     |> assign(:page_title, root.title)
     |> assign(:deleted_node, nil)
     |> assign(:undo_timer, nil)
     |> assign(:editing_node_id, nil)}
  end

  defp get_root_node(%{"id" => id}), do: MindMaps.get_node!(id)
  defp get_root_node(_), do: MindMaps.get_or_create_global_root()

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:modal_action, nil)
  end

  defp apply_action(socket, :new_child, _params) do
    # Now creating nodes inline, so just create one immediately and start editing
    parent_id = socket.assigns.focused_node_id
    {:ok, new_node} = MindMaps.create_child_node(parent_id, %{"title" => "New node"})

    socket
    |> reload_tree()
    |> assign(:modal_action, nil)
    |> assign(:focused_node_id, new_node.id)
    |> assign(:editing_node_id, new_node.id)
  end

  defp apply_action(socket, :edit, %{"node_id" => node_id}) do
    node = MindMaps.get_node!(node_id)

    socket
    |> assign(:modal_action, :edit)
    |> assign(:form_node, node)
  end

  @impl true
  def handle_event("focus_node", %{"id" => id}, socket) do
    id = String.to_integer(id)

    {:noreply, assign(socket, :focused_node_id, id)}
  end

  def handle_event("open_node_detail", %{"id" => id}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    node = Enum.find(socket.assigns.nodes, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:focused_node_id, id)
     |> assign(:selected_node, node)}
  end

  def handle_event("close_detail", _, socket) do
    {:noreply, assign(socket, :selected_node, nil)}
  end

  def handle_event("navigate", %{"direction" => direction}, socket) do
    new_focus = navigate(socket, direction)
    {:noreply, assign(socket, :focused_node_id, new_focus)}
  end

  def handle_event("toggle_todo", %{"id" => id}, socket) do
    node = MindMaps.get_node!(id)
    {:ok, _} = MindMaps.toggle_todo(node)
    {:noreply, reload_tree(socket)}
  end

  def handle_event("delete_node", %{"id" => id}, socket) do
    node = MindMaps.get_node!(id)
    delete_node_with_undo(socket, node)
  end

  def handle_event("undo_delete", _, socket) do
    case socket.assigns.deleted_node do
      nil ->
        {:noreply, socket}

      deleted_data ->
        # Cancel the timer
        if socket.assigns.undo_timer, do: Process.cancel_timer(socket.assigns.undo_timer)

        # Restore the node
        {:ok, restored} = MindMaps.create_child_node(deleted_data.parent_id, %{
          "title" => deleted_data.title,
          "body" => deleted_data.body || %{},
          "is_todo" => deleted_data.is_todo,
          "todo_completed" => deleted_data.todo_completed,
          "edge_label" => deleted_data.edge_label
        })

        {:noreply,
         socket
         |> reload_tree()
         |> assign(:deleted_node, nil)
         |> assign(:undo_timer, nil)
         |> assign(:focused_node_id, restored.id)}
    end
  end

  def handle_event("dismiss_undo", _, socket) do
    if socket.assigns.undo_timer, do: Process.cancel_timer(socket.assigns.undo_timer)

    {:noreply,
     socket
     |> assign(:deleted_node, nil)
     |> assign(:undo_timer, nil)}
  end

  def handle_event("focus_subtree", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/node/#{id}")}
  end

  def handle_event("keydown", %{"key" => key}, socket) do
    # Ignore keyboard shortcuts while editing a node title
    if socket.assigns.editing_node_id do
      {:noreply, socket}
    else
      handle_key(socket, key)
    end
  end

  def handle_event("save_inline_edit", %{"title" => title, "id" => id}, socket) do
    node_id = String.to_integer(id)
    node = MindMaps.get_node!(node_id)
    title = String.trim(title)

    if title == "" do
      # Delete node if title is empty
      {:ok, _} = MindMaps.delete_node(node)

      {:noreply,
       socket
       |> reload_tree()
       |> assign(:editing_node_id, nil)
       |> assign(:focused_node_id, node.parent_id || socket.assigns.root.id)}
    else
      {:ok, _} = MindMaps.update_node(node, %{title: title})

      {:noreply,
       socket
       |> reload_tree()
       |> assign(:editing_node_id, nil)}
    end
  end

  def handle_event("cancel_inline_edit", %{"id" => id}, socket) do
    node_id = String.to_integer(id)
    node = MindMaps.get_node!(node_id)

    # If the node has a placeholder title, delete it
    if node.title == "New node" do
      {:ok, _} = MindMaps.delete_node(node)

      {:noreply,
       socket
       |> reload_tree()
       |> assign(:editing_node_id, nil)
       |> assign(:focused_node_id, node.parent_id || socket.assigns.root.id)}
    else
      {:noreply, assign(socket, :editing_node_id, nil)}
    end
  end

  def handle_event("start_inline_edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_node_id, String.to_integer(id))}
  end

  def handle_event("blur_inline_edit", %{"value" => title} = params, socket) do
    # If we're no longer editing, ignore this blur event (already handled by cancel/submit)
    if socket.assigns.editing_node_id == nil do
      {:noreply, socket}
    else
      node_id = params["id"] |> String.to_integer()

      case MindMaps.get_node(node_id) do
        nil ->
          # Node was already deleted (e.g., by cancel), just clear editing state
          {:noreply, assign(socket, :editing_node_id, nil)}

        node ->
          title = String.trim(title)

          if title == "" do
            {:ok, _} = MindMaps.delete_node(node)

            {:noreply,
             socket
             |> reload_tree()
             |> assign(:editing_node_id, nil)
             |> assign(:focused_node_id, node.parent_id || socket.assigns.root.id)}
          else
            {:ok, _} = MindMaps.update_node(node, %{title: title})

            {:noreply,
             socket
             |> reload_tree()
             |> assign(:editing_node_id, nil)}
          end
      end
    end
  end

  def handle_event("add_node_inline", _, socket) do
    parent_id = socket.assigns.focused_node_id
    {:ok, new_node} = MindMaps.create_child_node(parent_id, %{"title" => "New node"})

    {:noreply,
     socket
     |> reload_tree()
     |> assign(:focused_node_id, new_node.id)
     |> assign(:editing_node_id, new_node.id)}
  end

  @impl true
  def handle_info({MindMapperPocWeb.MindMapLive.NodeFormComponent, {:saved, _node}}, socket) do
    {:noreply,
     socket
     |> reload_tree()
     |> assign(:selected_node, nil)}
  end

  def handle_info(:clear_undo, socket) do
    {:noreply,
     socket
     |> assign(:deleted_node, nil)
     |> assign(:undo_timer, nil)}
  end

  defp delete_node_with_undo(socket, node) do
    if node.id == socket.assigns.root.id do
      {:noreply,
       socket
       |> put_flash(:error, "Cannot delete the root node from this view")
       |> assign(:selected_node, nil)}
    else
      # Cancel any existing undo timer
      if socket.assigns.undo_timer, do: Process.cancel_timer(socket.assigns.undo_timer)

      # Store node data for potential undo
      deleted_data = %{
        title: node.title,
        body: node.body,
        is_todo: node.is_todo,
        todo_completed: node.todo_completed,
        edge_label: node.edge_label,
        parent_id: node.parent_id
      }

      # Reset focused node to parent or root before deleting
      new_focus = node.parent_id || socket.assigns.root.id
      {:ok, _} = MindMaps.delete_node(node)

      # Start timer to clear undo option
      timer_ref = Process.send_after(self(), :clear_undo, @undo_timeout)

      {:noreply,
       socket
       |> reload_tree()
       |> assign(:selected_node, nil)
       |> assign(:focused_node_id, new_focus)
       |> assign(:deleted_node, deleted_data)
       |> assign(:undo_timer, timer_ref)}
    end
  end

  defp handle_key(socket, "h"), do: {:noreply, navigate_to(socket, :parent)}
  defp handle_key(socket, "l"), do: {:noreply, navigate_to(socket, :child)}
  defp handle_key(socket, "j"), do: {:noreply, navigate_to(socket, :next_sibling)}
  defp handle_key(socket, "k"), do: {:noreply, navigate_to(socket, :prev_sibling)}

  defp handle_key(socket, "Backspace") do
    focused_id = socket.assigns.focused_node_id
    node = Enum.find(socket.assigns.nodes, &(&1.id == focused_id))

    if node do
      delete_node_with_undo(socket, node)
    else
      {:noreply, socket}
    end
  end

  defp handle_key(socket, "Enter") do
    node = Enum.find(socket.assigns.nodes, &(&1.id == socket.assigns.focused_node_id))
    {:noreply, assign(socket, :selected_node, node)}
  end

  defp handle_key(socket, "Escape") do
    {:noreply, assign(socket, :selected_node, nil)}
  end

  defp handle_key(socket, "o") do
    # Create node immediately with placeholder title
    parent_id = socket.assigns.focused_node_id
    {:ok, new_node} = MindMaps.create_child_node(parent_id, %{"title" => "New node"})

    {:noreply,
     socket
     |> reload_tree()
     |> assign(:focused_node_id, new_node.id)
     |> assign(:editing_node_id, new_node.id)}
  end

  defp handle_key(socket, "t") do
    node = Enum.find(socket.assigns.nodes, &(&1.id == socket.assigns.focused_node_id))

    if node && node.is_todo do
      {:ok, _} = MindMaps.toggle_todo(node)
      {:noreply, reload_tree(socket)}
    else
      {:noreply, socket}
    end
  end

  defp handle_key(socket, "f") do
    focused_id = socket.assigns.focused_node_id

    if focused_id != socket.assigns.root.id do
      {:noreply, push_navigate(socket, to: ~p"/node/#{focused_id}")}
    else
      {:noreply, socket}
    end
  end

  defp handle_key(socket, "Tab"), do: {:noreply, socket}
  defp handle_key(socket, _), do: {:noreply, socket}

  defp navigate_to(socket, direction) do
    nodes = socket.assigns.nodes
    focused_id = socket.assigns.focused_node_id
    current = Enum.find(nodes, &(&1.id == focused_id))

    new_id =
      case direction do
        :parent ->
          if current.parent_id && current.parent_id != socket.assigns.root.parent_id do
            current.parent_id
          else
            focused_id
          end

        :child ->
          children = Enum.filter(nodes, &(&1.parent_id == focused_id))
          first_child = Enum.min_by(children, & &1.position, fn -> nil end)
          if first_child, do: first_child.id, else: focused_id

        :next_sibling ->
          siblings =
            Enum.filter(nodes, &(&1.parent_id == current.parent_id && &1.id != focused_id))
            |> Enum.sort_by(&{&1.position, &1.id})

          # Find next sibling: higher position, or same position but higher id
          next = Enum.find(siblings, fn sib ->
            sib.position > current.position ||
              (sib.position == current.position && sib.id > current.id)
          end)
          if next, do: next.id, else: focused_id

        :prev_sibling ->
          siblings =
            Enum.filter(nodes, &(&1.parent_id == current.parent_id && &1.id != focused_id))
            |> Enum.sort_by(&{&1.position, &1.id}, :desc)

          # Find prev sibling: lower position, or same position but lower id
          prev = Enum.find(siblings, fn sib ->
            sib.position < current.position ||
              (sib.position == current.position && sib.id < current.id)
          end)
          if prev, do: prev.id, else: focused_id
      end

    assign(socket, :focused_node_id, new_id)
  end

  defp navigate(socket, "left"), do: navigate_to(socket, :parent).assigns.focused_node_id
  defp navigate(socket, "right"), do: navigate_to(socket, :child).assigns.focused_node_id
  defp navigate(socket, "down"), do: navigate_to(socket, :next_sibling).assigns.focused_node_id
  defp navigate(socket, "up"), do: navigate_to(socket, :prev_sibling).assigns.focused_node_id
  defp navigate(socket, _), do: socket.assigns.focused_node_id

  defp reload_tree(socket) do
    root = MindMaps.get_node!(socket.assigns.root.id)
    tree = MindMaps.get_subtree(root)
    node_positions = Layout.calculate_positions(tree)
    edges = Layout.calculate_edges(tree, node_positions)
    nodes = Layout.flatten_tree(tree)
    {_min_x, _min_y, max_x, max_y} = Layout.bounding_box(node_positions)

    socket
    |> assign(:root, root)
    |> assign(:tree, tree)
    |> assign(:node_positions, node_positions)
    |> assign(:edges, edges)
    |> assign(:nodes, nodes)
    |> assign(:canvas_width, max_x + 100)
    |> assign(:canvas_height, max_y + 100)
  end

  defp edge_path(edge) do
    # Create a curved bezier path from source to target
    mid_x = (edge.source_x + edge.target_x) / 2
    "M #{edge.source_x} #{edge.source_y} C #{mid_x} #{edge.source_y}, #{mid_x} #{edge.target_y}, #{edge.target_x} #{edge.target_y}"
  end
end
