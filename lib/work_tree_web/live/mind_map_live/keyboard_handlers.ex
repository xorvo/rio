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
  def handle_key(socket, "j", _opts), do: {:noreply, Navigation.navigate_to(socket, :next_sibling)}
  def handle_key(socket, "k", _opts), do: {:noreply, Navigation.navigate_to(socket, :prev_sibling)}

  # Delete with backspace
  def handle_key(socket, "Backspace", opts) do
    delete_fn = Keyword.fetch!(opts, :delete_fn)
    focused_id = socket.assigns.focused_node_id
    node = Enum.find(socket.assigns.nodes, &(&1.id == focused_id))

    if node do
      delete_fn.(socket, node)
    else
      {:noreply, socket}
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
     |> assign(:editing_node_id, new_node.id)}
  end

  # 't' to toggle todo state
  def handle_key(socket, "t", opts) do
    reload_fn = Keyword.fetch!(opts, :reload_fn)
    node = Enum.find(socket.assigns.nodes, &(&1.id == socket.assigns.focused_node_id))

    if node && node.is_todo do
      {:ok, _} = MindMaps.toggle_todo(node)
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

  # Ignore tab
  def handle_key(socket, "Tab", _opts), do: {:noreply, socket}

  # Default: ignore unhandled keys
  def handle_key(socket, _key, _opts), do: {:noreply, socket}
end
