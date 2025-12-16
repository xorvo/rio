defmodule WorkTreeWeb.MindMapLive.Show do
  use WorkTreeWeb, :live_view

  alias WorkTree.MindMaps
  alias WorkTree.MindMaps.Layout
  alias WorkTree.FuzzySearch
  alias WorkTreeWeb.MindMapLive.{Navigation, KeyboardHandlers}

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

  def handle_event("delete_node", %{"id" => id}, socket) do
    node = MindMaps.get_node!(id)
    delete_node_with_undo(socket, node)
  end

  def handle_event("undo_delete", _, socket) do
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
         |> reload_tree()
         |> assign(:deletion_batch, nil)
         |> assign(:undo_timer, nil)
         |> assign(:focused_node_id, focus_id)}
    end
  end

  def handle_event("dismiss_undo", _, socket) do
    if socket.assigns.undo_timer, do: Process.cancel_timer(socket.assigns.undo_timer)

    {:noreply,
     socket
     |> assign(:deletion_batch, nil)
     |> assign(:undo_timer, nil)}
  end

  def handle_event("confirm_delete", _, socket) do
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

  def handle_event("cancel_delete", _, socket) do
    {:noreply,
     socket
     |> assign(:pending_deletion, nil)}
  end

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
          delete_fn: &delete_node_with_undo/2,
          batch_delete_fn: &batch_delete_nodes/2,
          reload_fn: &reload_tree/1
        )
      end
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

  def handle_event("cancel_inline_edit", %{"id" => _id}, socket) do
    {:noreply, assign(socket, :editing_node_id, nil)}
  end

  def handle_event("inline_edit_keydown", %{"key" => "Escape", "id" => _id}, socket) do
    {:noreply, assign(socket, :editing_node_id, nil)}
  end

  def handle_event("inline_edit_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("start_inline_edit", %{"id" => id}, socket) do
    node_id = String.to_integer(id)

    {:noreply,
     socket
     |> assign(:editing_node_id, node_id)
     |> push_event("center-node", %{id: node_id})}
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
     |> assign(:editing_node_id, new_node.id)
     |> push_event("center-node", %{id: new_node.id})}
  end

  def handle_event("add_child_node", %{"parent-id" => parent_id}, socket) do
    parent_id = String.to_integer(parent_id)
    {:ok, new_node} = MindMaps.create_child_node(parent_id, %{"title" => "New node"})

    {:noreply,
     socket
     |> reload_tree()
     |> assign(:focused_node_id, new_node.id)
     |> assign(:editing_node_id, new_node.id)
     |> push_event("center-node", %{id: new_node.id})}
  end

  def handle_event("open_link_modal", %{"id" => id}, socket) do
    node = Enum.find(socket.assigns.nodes, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :link_edit_node, node)}
  end

  def handle_event("close_link_modal", _, socket) do
    {:noreply, assign(socket, :link_edit_node, nil)}
  end

  def handle_event("save_link", %{"link" => link}, socket) do
    node = socket.assigns.link_edit_node
    link = String.trim(link)

    # Allow empty string to clear the link
    link_value = if link == "", do: nil, else: link

    case MindMaps.update_node(node, %{link: link_value}) do
      {:ok, _updated_node} ->
        {:noreply,
         socket
         |> reload_tree()
         |> assign(:link_edit_node, nil)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Invalid URL. Must start with http:// or https://")}
    end
  end

  def handle_event("validate_link", _params, socket) do
    # Just ignore validation for now - HTML5 validation handles it
    {:noreply, socket}
  end

  def handle_event("open_node_link", %{"id" => id}, socket) do
    node = Enum.find(socket.assigns.nodes, &(&1.id == String.to_integer(id)))

    if node && node.link do
      {:noreply, push_event(socket, "open-link", %{url: node.link})}
    else
      {:noreply, socket}
    end
  end

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

  # Search events
  def handle_event("open_search", _, socket) do
    {:noreply,
     socket
     |> assign(:search_open, true)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:global_search_results, [])
     |> assign(:search_selected_index, 0)}
  end

  def handle_event("close_search", _, socket) do
    {:noreply,
     socket
     |> assign(:search_open, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:global_search_results, [])
     |> assign(:search_selected_index, 0)}
  end

  def handle_event("search", %{"query" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply,
       socket
       |> assign(:search_query, "")
       |> assign(:search_results, [])
       |> assign(:global_search_results, [])
       |> assign(:search_selected_index, 0)}
    else
      # Build ancestry map for local nodes
      local_nodes = socket.assigns.nodes
      local_ancestry_map = FuzzySearch.build_ancestry_map(local_nodes)
      local_results = FuzzySearch.search(local_nodes, query, ancestry_map: local_ancestry_map)
      local_node_ids = MapSet.new(local_nodes, & &1.id)

      # Get global nodes (excluding local subtree)
      all_nodes = MindMaps.get_all_nodes()
      global_nodes = Enum.reject(all_nodes, fn node -> MapSet.member?(local_node_ids, node.id) end)
      global_ancestry_map = FuzzySearch.build_ancestry_map(global_nodes)
      global_results = FuzzySearch.search(global_nodes, query, ancestry_map: global_ancestry_map)

      {:noreply,
       socket
       |> assign(:search_query, query)
       |> assign(:search_results, local_results)
       |> assign(:global_search_results, global_results)
       |> assign(:search_selected_index, 0)}
    end
  end

  def handle_event("search_select_prev", _, socket) do
    current = socket.assigns.search_selected_index
    results_count = total_search_results_count(socket)

    new_index =
      if results_count > 0 do
        rem(current - 1 + results_count, results_count)
      else
        0
      end

    {:noreply, assign(socket, :search_selected_index, new_index)}
  end

  def handle_event("search_select_next", _, socket) do
    current = socket.assigns.search_selected_index
    results_count = total_search_results_count(socket)

    new_index =
      if results_count > 0 do
        rem(current + 1, results_count)
      else
        0
      end

    {:noreply, assign(socket, :search_selected_index, new_index)}
  end

  def handle_event("search_go_to_result", %{"index" => index}, socket) do
    index = if is_binary(index), do: String.to_integer(index), else: index
    go_to_search_result(socket, index)
  end

  def handle_event("search_select_index", %{"index" => index}, socket) do
    index = if is_binary(index), do: String.to_integer(index), else: index
    {:noreply, assign(socket, :search_selected_index, index)}
  end

  def handle_event("search_confirm", _, socket) do
    index = socket.assigns.search_selected_index
    go_to_search_result(socket, index)
  end

  defp total_search_results_count(socket) do
    length(socket.assigns.search_results) + length(socket.assigns.global_search_results)
  end

  defp get_search_result_at(socket, index) do
    local_results = socket.assigns.search_results
    local_count = length(local_results)

    if index < local_count do
      Enum.at(local_results, index)
    else
      global_index = index - local_count
      Enum.at(socket.assigns.global_search_results, global_index)
    end
  end

  defp go_to_search_result(socket, index) do
    case get_search_result_at(socket, index) do
      {node, _score, _highlights, _ancestry} ->
        # Check if node is in the current subtree
        local_node_ids = MapSet.new(socket.assigns.nodes, & &1.id)
        is_local = MapSet.member?(local_node_ids, node.id)

        if is_local do
          {:noreply,
           socket
           |> assign(:search_open, false)
           |> assign(:search_query, "")
           |> assign(:search_results, [])
           |> assign(:global_search_results, [])
           |> assign(:search_selected_index, 0)
           |> assign(:focused_node_id, node.id)
           |> push_event("scroll-to-node", %{id: node.id})}
        else
          # Navigate to the node's parent view
          {:noreply,
           socket
           |> assign(:search_open, false)
           |> assign(:search_query, "")
           |> assign(:search_results, [])
           |> assign(:global_search_results, [])
           |> assign(:search_selected_index, 0)
           |> push_navigate(to: ~p"/node/#{node.id}")}
        end

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({WorkTreeWeb.MindMapLive.NodeFormComponent, {:saved, _node}}, socket) do
    {:noreply,
     socket
     |> reload_tree()
     |> assign(:selected_node, nil)}
  end

  def handle_info(:clear_undo, socket) do
    {:noreply,
     socket
     |> assign(:deletion_batch, nil)
     |> assign(:undo_timer, nil)}
  end

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
    delete_node_with_undo(socket, node)
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
    batch_delete_nodes(socket, node_ids)
  end

  def handle_info({:context_menu_action, :clear_selection}, socket) do
    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> assign(:selected_node_ids, MapSet.new())}
  end

  defp delete_node_with_undo(socket, node) do
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
         |> reload_tree()
         |> assign(:selected_node, nil)
         |> assign(:focused_node_id, new_focus)
         |> assign(:deletion_batch, deletion_info)
         |> assign(:undo_timer, timer_ref)
         |> assign(:pending_deletion, nil)}
    end
  end

  defp batch_delete_nodes(socket, node_ids) do
    root_id = socket.assigns.root.id

    # Filter out root node from deletion
    deletable_ids = Enum.reject(node_ids, &(&1 == root_id))

    if deletable_ids == [] do
      {:noreply,
       socket
       |> put_flash(:error, "Cannot delete the root node")}
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
         |> reload_tree()
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

  # Helper to get priority color class
  defp priority_color(0), do: "priority-p0"
  defp priority_color(1), do: "priority-p1"
  defp priority_color(2), do: "priority-p2"
  defp priority_color(3), do: "priority-p3"
  defp priority_color(_), do: ""

  # Helper to highlight text with match ranges
  defp highlight_text(text, []), do: text

  defp highlight_text(text, ranges) when is_binary(text) do
    graphemes = String.graphemes(text)
    total_len = length(graphemes)

    # Sort ranges by start position
    sorted_ranges = Enum.sort_by(ranges, fn {start, _stop} -> start end)

    # Build segments with highlight info
    {segments, last_pos} =
      Enum.reduce(sorted_ranges, {[], 0}, fn {start, stop}, {acc, pos} ->
        # Clamp positions to valid range
        start = max(0, min(start, total_len))
        stop = max(0, min(stop, total_len))

        if start >= stop or start < pos do
          {acc, pos}
        else
          # Add non-highlighted segment before this range
          before =
            if start > pos do
              [{:text, Enum.slice(graphemes, pos, start - pos) |> Enum.join()}]
            else
              []
            end

          # Add highlighted segment
          highlighted = [{:highlight, Enum.slice(graphemes, start, stop - start) |> Enum.join()}]

          {acc ++ before ++ highlighted, stop}
        end
      end)

    # Add remaining text after last highlight
    final_segments =
      if last_pos < total_len do
        segments ++ [{:text, Enum.slice(graphemes, last_pos, total_len - last_pos) |> Enum.join()}]
      else
        segments
      end

    # Convert to Phoenix HTML
    Phoenix.HTML.raw(
      Enum.map(final_segments, fn
        {:text, str} -> Phoenix.HTML.html_escape(str) |> Phoenix.HTML.safe_to_string()
        {:highlight, str} -> "<mark class=\"search-highlight\">#{Phoenix.HTML.html_escape(str) |> Phoenix.HTML.safe_to_string()}</mark>"
      end)
      |> Enum.join()
    )
  end

  # Helper to truncate body text
  defp truncate_body(nil), do: ""
  defp truncate_body(text) when is_binary(text) do
    if String.length(text) > 100 do
      String.slice(text, 0, 100) <> "..."
    else
      text
    end
  end
  defp truncate_body(_), do: ""

  # Helper to format ancestry path for display
  defp format_ancestry([]), do: ""
  defp format_ancestry(ancestors) when is_list(ancestors) do
    # Show truncated path: first / ... / last two
    case length(ancestors) do
      1 -> Enum.at(ancestors, 0)
      2 -> Enum.join(ancestors, " / ")
      _ ->
        first = Enum.at(ancestors, 0)
        last_two = Enum.take(ancestors, -2)
        "#{first} / ... / #{Enum.join(last_two, " / ")}"
    end
  end

  # Helper to count direct children of a node
  defp node_children_count(node, nodes) do
    nodes
    |> Enum.count(&(&1.parent_id == node.id))
  end

  # Helper to format date for display
  defp format_date(nil), do: "—"
  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end
end
