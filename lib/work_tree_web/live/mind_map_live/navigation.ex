defmodule WorkTreeWeb.MindMapLive.Navigation do
  @moduledoc """
  Keyboard navigation helpers for the mind map.
  Handles vim-style (h/j/k/l) and arrow key navigation.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias WorkTree.MindMaps.Tree

  @doc """
  Navigate to a relative position based on direction.
  Returns an updated socket with the new focused_node_id.
  """
  def navigate_to(socket, direction) do
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
          children =
            nodes
            |> Enum.filter(&(&1.parent_id == focused_id))
            |> Tree.sort_siblings()

          first_child = List.first(children)
          if first_child, do: first_child.id, else: focused_id

        :next_sibling ->
          all_siblings =
            nodes
            |> Enum.filter(&(&1.parent_id == current.parent_id))
            |> Tree.sort_siblings()

          current_index = Enum.find_index(all_siblings, &(&1.id == focused_id))
          next_index = rem(current_index + 1, length(all_siblings))
          Enum.at(all_siblings, next_index).id

        :prev_sibling ->
          all_siblings =
            nodes
            |> Enum.filter(&(&1.parent_id == current.parent_id))
            |> Tree.sort_siblings()

          current_index = Enum.find_index(all_siblings, &(&1.id == focused_id))
          prev_index = rem(current_index - 1 + length(all_siblings), length(all_siblings))
          Enum.at(all_siblings, prev_index).id

        :next_cousin ->
          find_next_cousin(nodes, current, socket.assigns.root.id)

        :prev_cousin ->
          find_prev_cousin(nodes, current, socket.assigns.root.id)
      end

    socket
    |> assign(:focused_node_id, new_id)
    |> push_event("scroll-to-node", %{id: new_id})
  end

  # Find the next node across subtrees at the same depth level
  defp find_next_cousin(nodes, current, root_id) do
    parent_id = current.parent_id

    # If at root level, just wrap siblings
    if parent_id == root_id or parent_id == nil do
      all_siblings =
        nodes
        |> Enum.filter(&(&1.parent_id == parent_id))
        |> Tree.sort_siblings()

      current_index = Enum.find_index(all_siblings, &(&1.id == current.id))
      next_index = rem(current_index + 1, length(all_siblings))
      Enum.at(all_siblings, next_index).id
    else
      # Get parent and its siblings (aunts/uncles)
      parent = Enum.find(nodes, &(&1.id == parent_id))

      parent_siblings =
        nodes
        |> Enum.filter(&(&1.parent_id == parent.parent_id))
        |> Tree.sort_siblings()

      # Get all children of all parent siblings (cousins + siblings), sorted by parent order
      all_cousins =
        parent_siblings
        |> Enum.flat_map(fn p ->
          nodes
          |> Enum.filter(&(&1.parent_id == p.id))
          |> Tree.sort_siblings()
        end)

      if Enum.empty?(all_cousins) do
        current.id
      else
        current_index = Enum.find_index(all_cousins, &(&1.id == current.id)) || 0
        next_index = rem(current_index + 1, length(all_cousins))
        Enum.at(all_cousins, next_index).id
      end
    end
  end

  # Find the previous node across subtrees at the same depth level
  defp find_prev_cousin(nodes, current, root_id) do
    parent_id = current.parent_id

    # If at root level, just wrap siblings
    if parent_id == root_id or parent_id == nil do
      all_siblings =
        nodes
        |> Enum.filter(&(&1.parent_id == parent_id))
        |> Tree.sort_siblings()

      current_index = Enum.find_index(all_siblings, &(&1.id == current.id))
      prev_index = rem(current_index - 1 + length(all_siblings), length(all_siblings))
      Enum.at(all_siblings, prev_index).id
    else
      # Get parent and its siblings (aunts/uncles)
      parent = Enum.find(nodes, &(&1.id == parent_id))

      parent_siblings =
        nodes
        |> Enum.filter(&(&1.parent_id == parent.parent_id))
        |> Tree.sort_siblings()

      # Get all children of all parent siblings (cousins + siblings), sorted by parent order
      all_cousins =
        parent_siblings
        |> Enum.flat_map(fn p ->
          nodes
          |> Enum.filter(&(&1.parent_id == p.id))
          |> Tree.sort_siblings()
        end)

      if Enum.empty?(all_cousins) do
        current.id
      else
        current_index = Enum.find_index(all_cousins, &(&1.id == current.id)) || 0
        prev_index = rem(current_index - 1 + length(all_cousins), length(all_cousins))
        Enum.at(all_cousins, prev_index).id
      end
    end
  end

  @doc """
  Navigate using arrow key direction strings.
  Returns the new focused_node_id.
  """
  def navigate(socket, "left"), do: navigate_to(socket, :parent).assigns.focused_node_id
  def navigate(socket, "right"), do: navigate_to(socket, :child).assigns.focused_node_id
  def navigate(socket, "down"), do: navigate_to(socket, :next_sibling).assigns.focused_node_id
  def navigate(socket, "up"), do: navigate_to(socket, :prev_sibling).assigns.focused_node_id
  def navigate(socket, _), do: socket.assigns.focused_node_id
end
