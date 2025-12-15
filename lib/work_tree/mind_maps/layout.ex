defmodule WorkTree.MindMaps.Layout do
  @moduledoc """
  Calculates automatic layout positions for mind map nodes.
  Uses a horizontal tree layout algorithm (root on left, children branch right).
  """

  @node_width 180
  @node_height 50
  @horizontal_gap 60
  @vertical_gap 20

  @doc """
  Calculates positions for all nodes in a tree.
  Takes a nested tree structure (node with :children key).
  Returns a map of node_id => %{x, y, width, height}.
  """
  def calculate_positions(tree, opts \\ []) do
    start_x = Keyword.get(opts, :start_x, 50)
    start_y = Keyword.get(opts, :start_y, 50)

    {layout, _} = layout_node(tree, start_x, start_y)
    layout
  end

  defp layout_node(node, x, y) do
    children = Map.get(node, :children, [])

    if Enum.empty?(children) do
      # Leaf node
      layout = %{
        node.id => %{
          x: x,
          y: y,
          width: @node_width,
          height: @node_height
        }
      }

      {layout, @node_height}
    else
      # Internal node - layout children first
      child_x = x + @node_width + @horizontal_gap

      {children_layouts, children_heights, _} =
        Enum.reduce(children, {%{}, [], y}, fn child, {acc_layout, acc_heights, current_y} ->
          {child_layout, child_height} = layout_node(child, child_x, current_y)
          merged_layout = Map.merge(acc_layout, child_layout)
          next_y = current_y + child_height + @vertical_gap
          {merged_layout, acc_heights ++ [child_height], next_y}
        end)

      # Calculate total height of children
      total_children_height =
        Enum.sum(children_heights) + @vertical_gap * (length(children) - 1)

      # Center parent vertically relative to children
      parent_y = y + (total_children_height - @node_height) / 2

      parent_layout = %{
        node.id => %{
          x: x,
          y: parent_y,
          width: @node_width,
          height: @node_height
        }
      }

      {Map.merge(children_layouts, parent_layout), total_children_height}
    end
  end

  @doc """
  Calculates edge data (source and target positions) for drawing connections.
  Takes a nested tree and a layout map.
  Returns a list of edge maps with source/target coordinates.
  """
  def calculate_edges(tree, layout) do
    collect_edges(tree, layout)
  end

  defp collect_edges(node, layout) do
    children = Map.get(node, :children, [])
    parent_pos = Map.get(layout, node.id)

    child_edges =
      Enum.map(children, fn child ->
        child_pos = Map.get(layout, child.id)

        %{
          source_id: node.id,
          target_id: child.id,
          source_x: parent_pos.x + parent_pos.width,
          source_y: parent_pos.y + parent_pos.height / 2,
          target_x: child_pos.x,
          target_y: child_pos.y + child_pos.height / 2,
          label: child.edge_label
        }
      end)

    descendant_edges =
      Enum.flat_map(children, fn child ->
        collect_edges(child, layout)
      end)

    child_edges ++ descendant_edges
  end

  @doc """
  Flattens a nested tree into a list of nodes.
  """
  def flatten_tree(tree) do
    children = Map.get(tree, :children, [])
    [tree | Enum.flat_map(children, &flatten_tree/1)]
  end

  @doc """
  Calculates the bounding box for the entire tree layout.
  Returns {min_x, min_y, max_x, max_y}.
  """
  def bounding_box(layout) when map_size(layout) == 0 do
    {0, 0, 0, 0}
  end

  def bounding_box(layout) do
    positions = Map.values(layout)

    min_x = positions |> Enum.map(& &1.x) |> Enum.min()
    min_y = positions |> Enum.map(& &1.y) |> Enum.min()
    max_x = positions |> Enum.map(&(&1.x + &1.width)) |> Enum.max()
    max_y = positions |> Enum.map(&(&1.y + &1.height)) |> Enum.max()

    {min_x, min_y, max_x, max_y}
  end
end
