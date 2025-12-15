defmodule WorkTreeWeb.MindMapLive.Navigation do
  @moduledoc """
  Keyboard navigation helpers for the mind map.
  Handles vim-style (h/j/k/l) and arrow key navigation.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

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
          children = Enum.filter(nodes, &(&1.parent_id == focused_id))
          first_child = Enum.min_by(children, & &1.position, fn -> nil end)
          if first_child, do: first_child.id, else: focused_id

        :next_sibling ->
          siblings =
            Enum.filter(nodes, &(&1.parent_id == current.parent_id && &1.id != focused_id))
            |> Enum.sort_by(&{&1.position, &1.id})

          next =
            Enum.find(siblings, fn sib ->
              sib.position > current.position ||
                (sib.position == current.position && sib.id > current.id)
            end)

          if next, do: next.id, else: focused_id

        :prev_sibling ->
          siblings =
            Enum.filter(nodes, &(&1.parent_id == current.parent_id && &1.id != focused_id))
            |> Enum.sort_by(&{&1.position, &1.id}, :desc)

          prev =
            Enum.find(siblings, fn sib ->
              sib.position < current.position ||
                (sib.position == current.position && sib.id < current.id)
            end)

          if prev, do: prev.id, else: focused_id
      end

    socket
    |> assign(:focused_node_id, new_id)
    |> push_event("scroll-to-node", %{id: new_id})
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
