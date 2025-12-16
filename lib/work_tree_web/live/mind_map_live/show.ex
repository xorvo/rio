defmodule WorkTreeWeb.MindMapLive.Show do
  use WorkTreeWeb, :live_view

  alias WorkTree.MindMaps
  alias WorkTree.MindMaps.Layout
  alias WorkTreeWeb.MindMapLive.{Navigation, KeyboardHandlers, Helpers, SearchHandlers, DeletionHandlers, InlineEditHandlers, LinkHandlers}

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
     |> assign(:deletion_batch, nil)
     |> assign(:undo_timer, nil)
     |> assign(:editing_node_id, nil)
     |> assign(:link_edit_node, nil)
     |> assign(:context_menu, nil)
     |> assign(:hints_expanded, false)
     |> assign(:search_open, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:global_search_results, [])
     |> assign(:search_selected_index, 0)
     |> assign(:selected_node_ids, MapSet.new())
     |> assign(:pending_deletion, nil)}
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
    |> push_event("center-node", %{id: new_node.id})
  end

  defp apply_action(socket, :edit, %{"node_id" => node_id}) do
    node = MindMaps.get_node!(node_id)

    socket
    |> assign(:modal_action, :edit)
    |> assign(:form_node, node)
  end

  @impl true
  def handle_event("focus_node", %{"id" => id} = params, socket) do
    id = String.to_integer(id)
    meta_key = params["metaKey"] || params["ctrlKey"] || false

    if meta_key do
      # Cmd+click toggles selection
      selected_ids = socket.assigns.selected_node_ids
      new_selected = if MapSet.member?(selected_ids, id) do
        MapSet.delete(selected_ids, id)
      else
        MapSet.put(selected_ids, id)
      end

      {:noreply,
       socket
       |> assign(:focused_node_id, id)
       |> assign(:selected_node_ids, new_selected)}
    else
      # Regular click clears selection and focuses
      {:noreply,
       socket
       |> assign(:focused_node_id, id)
       |> assign(:selected_node_ids, MapSet.new())
       |> push_event("scroll-to-node", %{id: id})}
    end
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
    new_focus = Navigation.navigate(socket, direction)

    {:noreply,
     socket
     |> assign(:focused_node_id, new_focus)
     |> push_event("scroll-to-node", %{id: new_focus})}
  end

  def handle_event("toggle_todo", %{"id" => id}, socket) do
    node = MindMaps.get_node!(id)
    {:ok, _} = MindMaps.toggle_todo(node)
    {:noreply, reload_tree(socket)}
  end

  # Deletion events - delegate to DeletionHandlers
  def handle_event("delete_node", %{"id" => id}, socket) do
    node = MindMaps.get_node!(id)
    DeletionHandlers.delete_node_with_undo(socket, node)
  end

  def handle_event("undo_delete", _, socket), do: DeletionHandlers.undo_delete(socket)
  def handle_event("dismiss_undo", _, socket), do: DeletionHandlers.dismiss_undo(socket)
  def handle_event("confirm_delete", _, socket), do: DeletionHandlers.confirm_delete(socket)
  def handle_event("cancel_delete", _, socket), do: DeletionHandlers.cancel_delete(socket)

  def handle_event("focus_subtree", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/node/#{id}")}
  end

  def handle_event("keydown", %{"key" => key} = params, socket) do
    meta_key = params["metaKey"] || false
    ctrl_key = params["ctrlKey"] || false

    # Handle Cmd+P / Ctrl+P to open search (works globally)
    if key == "p" and (meta_key or ctrl_key) do
      {:noreply, assign(socket, :search_open, true)}
    else
      # Ignore keyboard shortcuts while any modal or input is active
      modal_active = socket.assigns.editing_node_id ||
                     socket.assigns.link_edit_node ||
                     socket.assigns.selected_node ||
                     socket.assigns.modal_action ||
                     socket.assigns.search_open

      if modal_active do
        {:noreply, socket}
      else
        KeyboardHandlers.handle_key(socket, key,
          delete_fn: &DeletionHandlers.delete_node_with_undo/2,
          batch_delete_fn: &DeletionHandlers.batch_delete_nodes/2,
          reload_fn: &reload_tree/1
        )
      end
    end
  end

  # Inline edit events - delegate to InlineEditHandlers
  def handle_event("save_inline_edit", params, socket), do: InlineEditHandlers.save_inline_edit(socket, params)
  def handle_event("cancel_inline_edit", _params, socket), do: InlineEditHandlers.cancel_inline_edit(socket)
  def handle_event("inline_edit_keydown", params, socket), do: InlineEditHandlers.handle_keydown(socket, params)
  def handle_event("start_inline_edit", params, socket), do: InlineEditHandlers.start_inline_edit(socket, params)
  def handle_event("blur_inline_edit", params, socket), do: InlineEditHandlers.blur_inline_edit(socket, params)
  def handle_event("add_node_inline", _, socket), do: InlineEditHandlers.add_node_inline(socket)
  def handle_event("add_child_node", params, socket), do: InlineEditHandlers.add_child_node(socket, params)

  # Link events - delegate to LinkHandlers
  def handle_event("open_link_modal", params, socket), do: LinkHandlers.open_link_modal(socket, params)
  def handle_event("close_link_modal", _, socket), do: LinkHandlers.close_link_modal(socket)
  def handle_event("save_link", params, socket), do: LinkHandlers.save_link(socket, params)
  def handle_event("validate_link", _params, socket), do: LinkHandlers.validate_link(socket)
  def handle_event("open_node_link", params, socket), do: LinkHandlers.open_node_link(socket, params)

  # Context menu events
  def handle_event("open_context_menu", %{"id" => id, "x" => x, "y" => y}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    node = Enum.find(socket.assigns.nodes, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:focused_node_id, id)
     |> assign(:context_menu, %{node: node, x: x, y: y})}
  end

  def handle_event("close_context_menu", _, socket) do
    {:noreply, assign(socket, :context_menu, nil)}
  end

  # Search events - delegate to SearchHandlers
  def handle_event("open_search", _, socket), do: SearchHandlers.open_search(socket)
  def handle_event("close_search", _, socket), do: SearchHandlers.close_search(socket)
  def handle_event("search", params, socket), do: SearchHandlers.handle_search(socket, params)
  def handle_event("search_select_prev", _, socket), do: SearchHandlers.select_prev(socket)
  def handle_event("search_select_next", _, socket), do: SearchHandlers.select_next(socket)
  def handle_event("search_go_to_result", %{"index" => index}, socket), do: SearchHandlers.go_to_result(socket, index)
  def handle_event("search_select_index", %{"index" => index}, socket), do: SearchHandlers.select_index(socket, index)
  def handle_event("search_confirm", _, socket), do: SearchHandlers.confirm_selection(socket)

  @impl true
  def handle_info({WorkTreeWeb.MindMapLive.NodeFormComponent, {:saved, _node}}, socket) do
    {:noreply,
     socket
     |> reload_tree()
     |> assign(:selected_node, nil)}
  end

  def handle_info(:clear_undo, socket), do: DeletionHandlers.handle_clear_undo(socket)

  # Context menu action handlers
  def handle_info({:close_context_menu, _}, socket) do
    {:noreply, assign(socket, :context_menu, nil)}
  end

  def handle_info({:context_menu_action, :add_child, node}, socket) do
    {:ok, new_node} = MindMaps.create_child_node(node.id, %{"title" => "New node"})

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> reload_tree()
     |> assign(:focused_node_id, new_node.id)
     |> assign(:editing_node_id, new_node.id)
     |> push_event("center-node", %{id: new_node.id})}
  end

  def handle_info({:context_menu_action, :edit_node, node}, socket) do
    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> assign(:selected_node, node)}
  end

  def handle_info({:context_menu_action, :toggle_todo, node}, socket) do
    # Toggle is_todo status
    new_is_todo = !node.is_todo
    {:ok, _} = MindMaps.update_node(node, %{is_todo: new_is_todo, todo_completed: false})

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> reload_tree()}
  end

  def handle_info({:context_menu_action, :toggle_completed, node}, socket) do
    {:ok, _} = MindMaps.toggle_todo(node)

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> reload_tree()}
  end

  def handle_info({:context_menu_action, :set_priority, node, priority}, socket) do
    {:ok, _} = MindMaps.update_node(node, %{priority: priority})

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> reload_tree()}
  end

  def handle_info({:context_menu_action, :clear_priority, node}, socket) do
    {:ok, _} = MindMaps.update_node(node, %{priority: nil})

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> reload_tree()}
  end

  def handle_info({:context_menu_action, :edit_link, node}, socket) do
    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> assign(:link_edit_node, node)}
  end

  def handle_info({:context_menu_action, :open_link, node}, socket) do
    socket =
      if node.link do
        push_event(socket, "open-link", %{url: node.link})
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:context_menu, nil)}
  end

  def handle_info({:context_menu_action, :focus_subtree, node}, socket) do
    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> push_navigate(to: ~p"/node/#{node.id}")}
  end

  def handle_info({:context_menu_action, :toggle_lock, node}, socket) do
    {:ok, _} = MindMaps.toggle_lock(node)

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> reload_tree()}
  end

  def handle_info({:context_menu_action, :delete_node, node}, socket) do
    socket = assign(socket, :context_menu, nil)
    DeletionHandlers.delete_node_with_undo(socket, node)
  end

  # Batch action handlers from context menu
  def handle_info({:context_menu_action, :batch_make_todo, node_ids}, socket) do
    Enum.each(node_ids, fn id ->
      node = MindMaps.get_node!(id)
      MindMaps.update_node(node, %{is_todo: true})
    end)

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> assign(:selected_node_ids, MapSet.new())
     |> reload_tree()}
  end

  def handle_info({:context_menu_action, :batch_remove_todo, node_ids}, socket) do
    Enum.each(node_ids, fn id ->
      node = MindMaps.get_node!(id)
      MindMaps.update_node(node, %{is_todo: false, todo_completed: false})
    end)

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> assign(:selected_node_ids, MapSet.new())
     |> reload_tree()}
  end

  def handle_info({:context_menu_action, :batch_mark_complete, node_ids}, socket) do
    Enum.each(node_ids, fn id ->
      node = MindMaps.get_node!(id)
      if node.is_todo do
        MindMaps.update_node(node, %{todo_completed: true})
      end
    end)

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> assign(:selected_node_ids, MapSet.new())
     |> reload_tree()}
  end

  def handle_info({:context_menu_action, :batch_mark_incomplete, node_ids}, socket) do
    Enum.each(node_ids, fn id ->
      node = MindMaps.get_node!(id)
      if node.is_todo do
        MindMaps.update_node(node, %{todo_completed: false})
      end
    end)

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> assign(:selected_node_ids, MapSet.new())
     |> reload_tree()}
  end

  def handle_info({:context_menu_action, :batch_set_priority, node_ids, priority}, socket) do
    Enum.each(node_ids, fn id ->
      node = MindMaps.get_node!(id)
      MindMaps.update_node(node, %{priority: priority})
    end)

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> assign(:selected_node_ids, MapSet.new())
     |> reload_tree()}
  end

  def handle_info({:context_menu_action, :batch_clear_priority, node_ids}, socket) do
    Enum.each(node_ids, fn id ->
      node = MindMaps.get_node!(id)
      MindMaps.update_node(node, %{priority: nil})
    end)

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> assign(:selected_node_ids, MapSet.new())
     |> reload_tree()}
  end

  def handle_info({:context_menu_action, :batch_delete, node_ids}, socket) do
    socket = assign(socket, :context_menu, nil)
    DeletionHandlers.batch_delete_nodes(socket, node_ids)
  end

  def handle_info({:context_menu_action, :clear_selection}, socket) do
    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> assign(:selected_node_ids, MapSet.new())}
  end

  defp reload_tree(socket), do: Helpers.reload_tree(socket)

  # Delegate helper functions to Helpers module
  defp edge_path(edge), do: Helpers.edge_path(edge)
  defp priority_color(priority), do: Helpers.priority_class(priority, :css)
  defp node_children_count(node, nodes), do: Helpers.node_children_count(node, nodes)
end
