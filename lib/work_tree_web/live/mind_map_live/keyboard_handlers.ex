defmodule WorkTreeWeb.MindMapLive.KeyboardHandlers do
  @moduledoc """
  Keyboard shortcut handlers for the mind map.
  Maps vim-style keys to actions.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2]
  alias WorkTree.MindMaps
  alias WorkTreeWeb.MindMapLive.Navigation

  @doc """
  Handle a keydown event and return the appropriate response.
  """
  def handle_key(socket, key, opts \\ [])

  # Vim navigation keys
  def handle_key(socket, "h", _opts), do: {:noreply, Navigation.navigate_to(socket, :parent)}
  def handle_key(socket, "l", _opts), do: {:noreply, Navigation.navigate_to(socket, :child)}
  def handle_key(socket, "L", _opts), do: {:noreply, Navigation.navigate_to(socket, :child)}
  def handle_key(socket, "j", _opts), do: {:noreply, Navigation.navigate_to(socket, :next_sibling)}
  def handle_key(socket, "k", _opts), do: {:noreply, Navigation.navigate_to(socket, :prev_sibling)}

  # Capital J/K to jump across subtrees (cousins)
  def handle_key(socket, "J", _opts), do: {:noreply, Navigation.navigate_to(socket, :next_cousin)}
  def handle_key(socket, "K", _opts), do: {:noreply, Navigation.navigate_to(socket, :prev_cousin)}

  # Delete with backspace or x - supports batch delete
  def handle_key(socket, key, opts) when key in ["Backspace", "x"] do
    selected_ids = socket.assigns.selected_node_ids

    if MapSet.size(selected_ids) > 0 do
      # Batch delete selected nodes
      batch_delete_fn = Keyword.fetch!(opts, :batch_delete_fn)
      batch_delete_fn.(socket, MapSet.to_list(selected_ids))
    else
      # Single delete focused node
      delete_fn = Keyword.fetch!(opts, :delete_fn)
      focused_id = socket.assigns.focused_node_id
      node = Enum.find(socket.assigns.nodes, &(&1.id == focused_id))

      if node do
        delete_fn.(socket, node)
      else
        {:noreply, socket}
      end
    end
  end

  # Enter to open details
  def handle_key(socket, "Enter", _opts) do
    node = Enum.find(socket.assigns.nodes, &(&1.id == socket.assigns.focused_node_id))
    {:noreply, assign(socket, :selected_node, node)}
  end

  # Escape to close details
  def handle_key(socket, "Escape", _opts) do
    {:noreply, assign(socket, :selected_node, nil)}
  end

  # 'o' to create new child node
  def handle_key(socket, "o", opts) do
    reload_fn = Keyword.fetch!(opts, :reload_fn)
    parent_id = socket.assigns.focused_node_id
    {:ok, new_node} = MindMaps.create_child_node(parent_id, %{"title" => "New node"})

    {:noreply,
     socket
     |> reload_fn.()
     |> assign(:focused_node_id, new_node.id)
     |> assign(:editing_node_id, new_node.id)
     |> Phoenix.LiveView.push_event("center-node", %{id: new_node.id})}
  end

  # 'O' (Shift+o) to create new sibling node (no effect on root)
  def handle_key(socket, "O", opts) do
    focused_id = socket.assigns.focused_node_id
    node = Enum.find(socket.assigns.nodes, &(&1.id == focused_id))

    # Only create sibling if not the root node of current view
    if node && node.id != socket.assigns.root.id do
      reload_fn = Keyword.fetch!(opts, :reload_fn)
      {:ok, new_node} = MindMaps.create_sibling_node(node, %{"title" => "New node"})

      {:noreply,
       socket
       |> reload_fn.()
       |> assign(:focused_node_id, new_node.id)
       |> assign(:editing_node_id, new_node.id)
       |> Phoenix.LiveView.push_event("center-node", %{id: new_node.id})}
    else
      {:noreply, socket}
    end
  end

  # 't' to toggle todo state (converts to todo if not already)
  def handle_key(socket, "t", opts) do
    reload_fn = Keyword.fetch!(opts, :reload_fn)
    node = Enum.find(socket.assigns.nodes, &(&1.id == socket.assigns.focused_node_id))

    if node do
      if node.is_todo do
        # Toggle completion status
        {:ok, _} = MindMaps.toggle_todo(node)
      else
        # Convert to todo
        {:ok, _} = MindMaps.update_node(node, %{is_todo: true})
      end
      {:noreply, reload_fn.(socket)}
    else
      {:noreply, socket}
    end
  end

  # 'f' to focus subtree
  def handle_key(socket, "f", _opts) do
    focused_id = socket.assigns.focused_node_id

    if focused_id != socket.assigns.root.id do
      {:noreply, push_navigate(socket, to: "/node/#{focused_id}")}
    else
      {:noreply, socket}
    end
  end

  # 'H' (Shift+h) - on root node: jump up one level; otherwise: same as 'h' (navigate to parent)
  def handle_key(socket, "H", _opts) do
    focused_id = socket.assigns.focused_node_id
    root_id = socket.assigns.root.id
    ancestors = socket.assigns.ancestors

    if focused_id == root_id and ancestors != [] do
      # Navigate to the parent node view (one level up)
      parent = List.last(ancestors)
      {:noreply, push_navigate(socket, to: "/node/#{parent.id}")}
    else
      # Same as lowercase 'h' - navigate to parent within tree
      {:noreply, Navigation.navigate_to(socket, :parent)}
    end
  end

  # 'i' to start inline editing on focused node
  def handle_key(socket, "i", _opts) do
    focused_id = socket.assigns.focused_node_id

    {:noreply,
     socket
     |> assign(:editing_node_id, focused_id)
     |> Phoenix.LiveView.push_event("center-node", %{id: focused_id})}
  end

  # 'a' to attach/edit link (quick inline input)
  def handle_key(socket, "a", _opts) do
    node = Enum.find(socket.assigns.nodes, &(&1.id == socket.assigns.focused_node_id))

    {:noreply,
     socket
     |> assign(:link_input_open, true)
     |> assign(:link_input_node, node)}
  end

  # 'g' to go to (open) link - handled via JS hook reading data-node-link attribute
  def handle_key(socket, "g", _opts) do
    focused_id = socket.assigns.focused_node_id
    {:noreply, Phoenix.LiveView.push_event(socket, "open-focused-node-link", %{node_id: focused_id})}
  end

  # Space to toggle hints expansion
  def handle_key(socket, " ", _opts) do
    {:noreply, assign(socket, :hints_expanded, !socket.assigns.hints_expanded)}
  end

  # 'T' (Shift+t) to open search
  def handle_key(socket, "T", _opts) do
    {:noreply, assign(socket, :search_open, true)}
  end

  # 'p' to open priority picker
  def handle_key(socket, "p", _opts) do
    {:noreply, assign(socket, :priority_picker_open, true)}
  end

  # 'd' to open due date picker
  def handle_key(socket, "d", _opts) do
    {:noreply, assign(socket, :due_date_picker_open, true)}
  end

  # Ignore tab
  def handle_key(socket, "Tab", _opts), do: {:noreply, socket}

  # Default: ignore unhandled keys
  def handle_key(socket, _key, _opts), do: {:noreply, socket}
end
