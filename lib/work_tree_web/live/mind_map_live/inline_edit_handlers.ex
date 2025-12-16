defmodule WorkTreeWeb.MindMapLive.InlineEditHandlers do
  @moduledoc """
  Inline title editing handlers for mind map nodes.
  Handles in-place editing of node titles.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias WorkTree.MindMaps
  alias WorkTreeWeb.MindMapLive.Helpers

  @doc """
  Saves inline edit, updating the node title or deleting if empty.
  """
  def save_inline_edit(socket, %{"title" => title, "id" => id}) do
    node_id = String.to_integer(id)
    node = MindMaps.get_node!(node_id)
    title = String.trim(title)

    if title == "" do
      # Delete node if title is empty
      {:ok, _} = MindMaps.delete_node(node)

      {:noreply,
       socket
       |> Helpers.reload_tree()
       |> assign(:editing_node_id, nil)
       |> assign(:focused_node_id, node.parent_id || socket.assigns.root.id)}
    else
      {:ok, _} = MindMaps.update_node(node, %{title: title})

      {:noreply,
       socket
       |> Helpers.reload_tree()
       |> assign(:editing_node_id, nil)}
    end
  end

  @doc """
  Cancels inline edit without saving.
  """
  def cancel_inline_edit(socket) do
    {:noreply, assign(socket, :editing_node_id, nil)}
  end

  @doc """
  Handles keydown during inline edit.
  Escape cancels the edit.
  """
  def handle_keydown(socket, %{"key" => "Escape"}) do
    {:noreply, assign(socket, :editing_node_id, nil)}
  end

  def handle_keydown(socket, _params) do
    {:noreply, socket}
  end

  @doc """
  Starts inline editing for a node.
  """
  def start_inline_edit(socket, %{"id" => id}) do
    node_id = String.to_integer(id)

    {:noreply,
     socket
     |> assign(:editing_node_id, node_id)
     |> push_event("center-node", %{id: node_id})}
  end

  @doc """
  Handles blur event from inline edit input.
  Saves the edit or deletes if empty.
  """
  def blur_inline_edit(socket, %{"value" => title} = params) do
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
             |> Helpers.reload_tree()
             |> assign(:editing_node_id, nil)
             |> assign(:focused_node_id, node.parent_id || socket.assigns.root.id)}
          else
            {:ok, _} = MindMaps.update_node(node, %{title: title})

            {:noreply,
             socket
             |> Helpers.reload_tree()
             |> assign(:editing_node_id, nil)}
          end
      end
    end
  end

  @doc """
  Creates a new child node and starts inline editing.
  """
  def add_node_inline(socket) do
    parent_id = socket.assigns.focused_node_id
    {:ok, new_node} = MindMaps.create_child_node(parent_id, %{"title" => "New node"})

    {:noreply,
     socket
     |> Helpers.reload_tree()
     |> assign(:focused_node_id, new_node.id)
     |> assign(:editing_node_id, new_node.id)
     |> push_event("center-node", %{id: new_node.id})}
  end

  @doc """
  Creates a new child node under specified parent and starts inline editing.
  """
  def add_child_node(socket, %{"parent-id" => parent_id}) do
    parent_id = String.to_integer(parent_id)
    {:ok, new_node} = MindMaps.create_child_node(parent_id, %{"title" => "New node"})

    {:noreply,
     socket
     |> Helpers.reload_tree()
     |> assign(:focused_node_id, new_node.id)
     |> assign(:editing_node_id, new_node.id)
     |> push_event("center-node", %{id: new_node.id})}
  end
end
