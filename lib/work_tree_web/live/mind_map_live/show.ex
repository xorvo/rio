defmodule WorkTreeWeb.MindMapLive.Show do
  use WorkTreeWeb, :live_view

  alias WorkTree.MindMaps
  alias WorkTree.MindMaps.Layout

  alias WorkTreeWeb.MindMapLive.{
    Navigation,
    KeyboardHandlers,
    Helpers,
    SearchHandlers,
    DeletionHandlers,
    ArchiveHandlers,
    InlineEditHandlers,
    LinkHandlers,
    DragHandlers,
    TodoFilterHandlers
  }

  @impl true
  def mount(params, _session, socket) do
    case get_root_node(params) do
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Node not found")
         |> push_navigate(to: ~p"/")}

      {:ok, root} ->
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
         |> assign(:pending_deletion, nil)
         |> assign(:dragging_node, nil)
         |> assign(:drag_target_id, nil)
         |> assign(:pending_move, nil)
         |> assign(:move_undo_info, nil)
         |> assign(:move_undo_timer, nil)
         |> assign(:priority_picker_open, false)
         |> assign(:due_date_picker_open, false)
         |> assign(:due_date_custom_mode, false)
         |> assign(:link_input_open, false)
         |> assign(:link_input_node, nil)
         |> assign(:todo_filter_open, false)
         |> assign(:todo_filter_results, [])
         |> assign(:todo_filter_selected_index, 0)
         |> assign(:todo_filter_scope, :local)
         |> assign(:todo_filter_show_completed, false)
         # Archive-related assigns
         |> assign(:show_archived, false)
         |> assign(:pending_archive, nil)
         |> assign(:archive_batch, nil)
         |> assign(:archive_undo_timer, nil)
         # Theme picker
         |> assign(:theme_picker_open, false)}
    end
  end

  defp get_root_node(%{"id" => id}) do
    case MindMaps.get_node(id) do
      nil -> {:error, :not_found}
      node -> {:ok, node}
    end
  end

  defp get_root_node(_), do: {:ok, MindMaps.get_or_create_global_root()}

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
    meta_key = params["metaKey"] || params["ctrlKey"] || false

    if meta_key do
      # Cmd+click toggles selection
      selected_ids = socket.assigns.selected_node_ids

      new_selected =
        if MapSet.member?(selected_ids, id) do
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
    {:ok, updated_node} = MindMaps.toggle_todo(node)

    # Update selected_node if it's the same node (for modal refresh)
    socket =
      if socket.assigns.selected_node && socket.assigns.selected_node.id == id do
        assign(socket, :selected_node, updated_node)
      else
        socket
      end

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

  # Archive events - delegate to ArchiveHandlers
  def handle_event("archive_node", %{"id" => id}, socket) do
    node = MindMaps.get_node!(id)
    ArchiveHandlers.archive_node_with_undo(socket, node)
  end

  def handle_event("undo_archive", _, socket), do: ArchiveHandlers.undo_archive(socket)
  def handle_event("dismiss_archive_undo", _, socket), do: ArchiveHandlers.dismiss_archive_undo(socket)
  def handle_event("confirm_archive", _, socket), do: ArchiveHandlers.confirm_archive(socket)
  def handle_event("cancel_archive", _, socket), do: ArchiveHandlers.cancel_archive(socket)

  def handle_event("toggle_show_archived", _, socket) do
    new_show_archived = !socket.assigns.show_archived

    {:noreply,
     socket
     |> assign(:show_archived, new_show_archived)
     |> reload_tree()}
  end

  def handle_event("focus_subtree", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/node/#{id}")}
  end

  def handle_event("keydown", %{"isInputTarget" => true}, socket) do
    # Ignore keyboard events that originated from input/textarea elements
    {:noreply, socket}
  end

  def handle_event("keydown", event, socket) do
    # Ignore keyboard shortcuts while any modal or input is active
    modal_active =
      socket.assigns.editing_node_id ||
        socket.assigns.link_edit_node ||
        socket.assigns.selected_node ||
        socket.assigns.modal_action ||
        socket.assigns.search_open ||
        socket.assigns.priority_picker_open ||
        socket.assigns.due_date_picker_open ||
        socket.assigns.link_input_open ||
        socket.assigns.todo_filter_open

    if modal_active do
      {:noreply, socket}
    else
      KeyboardHandlers.handle_key(socket, event,
        delete_fn: &DeletionHandlers.delete_node_with_undo/2,
        batch_delete_fn: &DeletionHandlers.batch_delete_nodes/2,
        archive_fn: &ArchiveHandlers.archive_node_with_undo/2,
        reload_fn: &reload_tree/1
      )
    end
  end

  # Inline edit events - delegate to InlineEditHandlers
  def handle_event("save_inline_edit", params, socket),
    do: InlineEditHandlers.save_inline_edit(socket, params)

  def handle_event("cancel_inline_edit", _params, socket),
    do: InlineEditHandlers.cancel_inline_edit(socket)

  def handle_event("inline_edit_keydown", params, socket),
    do: InlineEditHandlers.handle_keydown(socket, params)

  def handle_event("start_inline_edit", params, socket),
    do: InlineEditHandlers.start_inline_edit(socket, params)

  def handle_event("blur_inline_edit", params, socket),
    do: InlineEditHandlers.blur_inline_edit(socket, params)

  def handle_event("add_node_inline", _, socket), do: InlineEditHandlers.add_node_inline(socket)

  def handle_event("add_child_node", params, socket),
    do: InlineEditHandlers.add_child_node(socket, params)

  # Link events - delegate to LinkHandlers
  def handle_event("open_link_modal", params, socket),
    do: LinkHandlers.open_link_modal(socket, params)

  def handle_event("close_link_modal", _, socket), do: LinkHandlers.close_link_modal(socket)
  def handle_event("save_link", params, socket), do: LinkHandlers.save_link(socket, params)
  def handle_event("validate_link", _params, socket), do: LinkHandlers.validate_link(socket)

  def handle_event("open_node_link", params, socket),
    do: LinkHandlers.open_node_link(socket, params)

  # Drag events - delegate to DragHandlers
  def handle_event("drag_start", %{"node_id" => node_id}, socket) do
    {:noreply, DragHandlers.start_drag(socket, node_id)}
  end

  def handle_event("drag_end", %{"node_id" => node_id, "target_id" => target_id}, socket) do
    {:noreply, DragHandlers.execute_move(socket, node_id, target_id)}
  end

  def handle_event("drag_cancel", _, socket) do
    {:noreply, DragHandlers.cancel_drag(socket)}
  end

  def handle_event("confirm_move", _, socket) do
    {:noreply, DragHandlers.confirm_move(socket)}
  end

  def handle_event("cancel_move", _, socket) do
    {:noreply, DragHandlers.cancel_pending_move(socket)}
  end

  def handle_event("undo_move", _, socket) do
    {:noreply, DragHandlers.undo_move(socket)}
  end

  def handle_event("dismiss_move_undo", _, socket) do
    {:noreply, DragHandlers.dismiss_undo(socket)}
  end

  # Context menu events
  def handle_event("open_context_menu", %{"id" => id, "x" => x, "y" => y}, socket) do
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

  def handle_event("search_go_to_result", %{"index" => index}, socket),
    do: SearchHandlers.go_to_result(socket, index)

  def handle_event("search_select_index", %{"index" => index}, socket),
    do: SearchHandlers.select_index(socket, index)

  def handle_event("search_confirm", _, socket), do: SearchHandlers.confirm_selection(socket)

  # Todo filter events - delegate to TodoFilterHandlers
  def handle_event("open_todo_filter", _, socket), do: TodoFilterHandlers.open_todo_filter(socket)

  def handle_event("close_todo_filter", _, socket),
    do: TodoFilterHandlers.close_todo_filter(socket)

  def handle_event("todo_filter_toggle_scope", _, socket),
    do: TodoFilterHandlers.toggle_scope(socket)

  def handle_event("todo_filter_set_scope", %{"scope" => "local"}, socket),
    do: TodoFilterHandlers.set_scope(socket, :local)

  def handle_event("todo_filter_set_scope", %{"scope" => "global"}, socket),
    do: TodoFilterHandlers.set_scope(socket, :global)

  def handle_event("todo_filter_toggle_completed", _, socket),
    do: TodoFilterHandlers.toggle_show_completed(socket)

  def handle_event("todo_filter_select_prev", _, socket),
    do: TodoFilterHandlers.select_prev(socket)

  def handle_event("todo_filter_select_next", _, socket),
    do: TodoFilterHandlers.select_next(socket)

  def handle_event("todo_filter_go_to_result", %{"index" => index}, socket),
    do: TodoFilterHandlers.go_to_result(socket, index)

  def handle_event("todo_filter_select_index", %{"index" => index}, socket),
    do: TodoFilterHandlers.select_index(socket, index)

  def handle_event("todo_filter_confirm", _, socket),
    do: TodoFilterHandlers.confirm_selection(socket)

  # Theme picker events
  def handle_event("open_theme_picker", _, socket) do
    {:noreply, assign(socket, :theme_picker_open, true)}
  end

  def handle_event("close_theme_picker", _, socket) do
    {:noreply, assign(socket, :theme_picker_open, false)}
  end

  def handle_event("theme_picker_keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, :theme_picker_open, false)}
  end

  def handle_event("theme_picker_keydown", _, socket) do
    {:noreply, socket}
  end

  # Priority picker events
  def handle_event("close_priority_picker", _, socket) do
    {:noreply, assign(socket, :priority_picker_open, false)}
  end

  def handle_event("priority_picker_keydown", %{"key" => key}, socket) do
    cond do
      key == "Escape" ->
        {:noreply, assign(socket, :priority_picker_open, false)}

      key in ["0", "1", "2", "3"] ->
        priority = String.to_integer(key)
        apply_priority(socket, priority)

      key in ["x", "X", "Backspace"] ->
        apply_priority(socket, nil)

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("priority_picker_select", %{"priority" => "clear"}, socket) do
    apply_priority(socket, nil)
  end

  def handle_event("priority_picker_select", %{"priority" => priority}, socket) do
    priority = String.to_integer(priority)
    apply_priority(socket, priority)
  end

  defp apply_priority(socket, priority) do
    selected_ids = socket.assigns.selected_node_ids

    if MapSet.size(selected_ids) > 0 do
      # Batch mode
      Enum.each(selected_ids, fn id ->
        node = MindMaps.get_node!(id)
        MindMaps.update_node(node, %{priority: priority})
      end)

      {:noreply,
       socket
       |> assign(:priority_picker_open, false)
       |> assign(:selected_node_ids, MapSet.new())
       |> reload_tree()}
    else
      # Single node mode
      node = Enum.find(socket.assigns.nodes, &(&1.id == socket.assigns.focused_node_id))

      if node do
        {:ok, _} = MindMaps.update_node(node, %{priority: priority})

        {:noreply,
         socket
         |> assign(:priority_picker_open, false)
         |> reload_tree()}
      else
        {:noreply, assign(socket, :priority_picker_open, false)}
      end
    end
  end

  # Due date picker events
  def handle_event("close_due_date_picker", _, socket) do
    {:noreply,
     socket
     |> assign(:due_date_picker_open, false)
     |> assign(:due_date_custom_mode, false)}
  end

  def handle_event("due_date_picker_keydown", %{"key" => key}, socket) do
    cond do
      key == "Escape" ->
        {:noreply,
         socket
         |> assign(:due_date_picker_open, false)
         |> assign(:due_date_custom_mode, false)}

      key in ["1", "2", "3", "4", "5"] ->
        apply_due_date_option(socket, String.to_integer(key))

      key == "6" ->
        # Switch to custom date mode
        {:noreply, assign(socket, :due_date_custom_mode, true)}

      key in ["x", "X", "Backspace"] ->
        apply_due_date(socket, nil)

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("due_date_picker_select", %{"option" => "clear"}, socket) do
    apply_due_date(socket, nil)
  end

  def handle_event("due_date_picker_select", %{"option" => "6"}, socket) do
    {:noreply, assign(socket, :due_date_custom_mode, true)}
  end

  def handle_event("due_date_picker_select", %{"option" => option}, socket) do
    apply_due_date_option(socket, String.to_integer(option))
  end

  def handle_event("due_date_custom_submit", %{"custom_date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        apply_due_date(socket, date)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid date")}
    end
  end

  def handle_event("due_date_cancel_custom", _, socket) do
    {:noreply, assign(socket, :due_date_custom_mode, false)}
  end

  defp apply_due_date_option(socket, option) do
    due_date = calculate_due_date(option)
    apply_due_date(socket, due_date)
  end

  defp calculate_due_date(option) do
    today = Date.utc_today()

    case option do
      1 -> today
      2 -> Date.add(today, 7)
      3 -> Date.add(today, 14)
      4 -> Date.add(today, 30)
      5 -> Date.add(today, 60)
      _ -> nil
    end
  end

  defp apply_due_date(socket, due_date) do
    selected_ids = socket.assigns.selected_node_ids

    if MapSet.size(selected_ids) > 0 do
      # Batch mode
      Enum.each(selected_ids, fn id ->
        node = MindMaps.get_node!(id)
        MindMaps.update_node(node, %{due_date: due_date})
      end)

      {:noreply,
       socket
       |> assign(:due_date_picker_open, false)
       |> assign(:due_date_custom_mode, false)
       |> assign(:selected_node_ids, MapSet.new())
       |> reload_tree()}
    else
      # Single node mode
      node = Enum.find(socket.assigns.nodes, &(&1.id == socket.assigns.focused_node_id))

      if node do
        {:ok, _} = MindMaps.update_node(node, %{due_date: due_date})

        {:noreply,
         socket
         |> assign(:due_date_picker_open, false)
         |> assign(:due_date_custom_mode, false)
         |> reload_tree()}
      else
        {:noreply,
         socket
         |> assign(:due_date_picker_open, false)
         |> assign(:due_date_custom_mode, false)}
      end
    end
  end

  # Link input events (quick inline link editor)
  def handle_event("close_link_input", _, socket) do
    {:noreply,
     socket
     |> assign(:link_input_open, false)
     |> assign(:link_input_node, nil)}
  end

  def handle_event("save_link_input", %{"link" => link}, socket) do
    node = socket.assigns.link_input_node
    link = String.trim(link)
    link_value = if link == "", do: nil, else: link

    case MindMaps.update_node(node, %{link: link_value}) do
      {:ok, _updated_node} ->
        {:noreply,
         socket
         |> assign(:link_input_open, false)
         |> assign(:link_input_node, nil)
         |> reload_tree()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Invalid URL")}
    end
  end

  def handle_event("link_input_keydown", %{"key" => "Escape"}, socket) do
    {:noreply,
     socket
     |> assign(:link_input_open, false)
     |> assign(:link_input_node, nil)}
  end

  def handle_event("link_input_keydown", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({WorkTreeWeb.MindMapLive.NodeFormComponent, {:saved, _node}}, socket) do
    {:noreply,
     socket
     |> reload_tree()
     |> assign(:selected_node, nil)}
  end

  def handle_info(:clear_undo, socket), do: DeletionHandlers.handle_clear_undo(socket)
  def handle_info(:clear_move_undo, socket), do: DragHandlers.handle_clear_move_undo(socket)
  def handle_info(:clear_archive_undo, socket), do: ArchiveHandlers.handle_clear_archive_undo(socket)

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

  def handle_info({:context_menu_action, :archive_node, node}, socket) do
    socket = assign(socket, :context_menu, nil)
    ArchiveHandlers.archive_node_with_undo(socket, node)
  end

  def handle_info({:context_menu_action, :unarchive_node, node}, socket) do
    {:ok, _} = MindMaps.unarchive_node(node)

    {:noreply,
     socket
     |> assign(:context_menu, nil)
     |> reload_tree()}
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
  defp due_date_class(due_date), do: Helpers.due_date_class(due_date)
  defp format_due_date_badge(due_date), do: Helpers.format_due_date_badge(due_date)
  defp node_children_count(node, nodes), do: Helpers.node_children_count(node, nodes)
  defp get_subtree_count(node, nodes), do: Helpers.get_subtree_count(node, nodes)
  defp get_descendant_ids(node, nodes), do: Helpers.get_descendant_ids(node, nodes)
end
