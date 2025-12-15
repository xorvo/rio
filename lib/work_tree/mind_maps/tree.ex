defmodule WorkTree.MindMaps.Tree do
  @moduledoc """
  Handles tree path operations for the mind map node hierarchy.
  Uses materialized path pattern for efficient subtree queries.
  """

  import Ecto.Query
  alias WorkTree.MindMaps.Node

  @doc """
  Builds the path for a new node given its parent and the node's own ID.
  Root nodes (no parent) have path equal to their ID as string.
  """
  def build_path(nil, node_id), do: "#{node_id}"
  def build_path(%Node{path: parent_path}, node_id), do: "#{parent_path}.#{node_id}"

  @doc """
  Calculates depth based on parent.
  """
  def calculate_depth(nil), do: 0
  def calculate_depth(%Node{depth: parent_depth}), do: parent_depth + 1

  @doc """
  Returns a query for all descendants of a node (subtree).
  Uses LIKE query on materialized path.
  """
  def descendants_query(%Node{path: path}) do
    pattern = "#{path}.%"
    from(n in Node, where: like(n.path, ^pattern))
  end

  @doc """
  Returns a query for all ancestors of a node.
  Parses path and returns nodes with matching IDs.
  """
  def ancestors_query(%Node{path: path}) do
    ancestor_ids =
      path
      |> String.split(".")
      |> Enum.drop(-1)
      |> Enum.map(&String.to_integer/1)

    from(n in Node, where: n.id in ^ancestor_ids, order_by: n.depth)
  end

  @doc """
  Returns a query for siblings of a node (nodes with same parent).
  """
  def siblings_query(%Node{parent_id: parent_id, id: id}) do
    from(n in Node,
      where: n.parent_id == ^parent_id and n.id != ^id,
      order_by: n.position
    )
  end

  @doc """
  Returns the next position for a new child under a parent.
  Uses max(position) + 1 to avoid duplicate positions after deletions.
  """
  def next_child_position(nil) do
    # For root nodes, get max position + 1
    from(n in Node,
      where: is_nil(n.parent_id),
      select: coalesce(max(n.position) + 1, 0)
    )
  end

  def next_child_position(%Node{id: parent_id}) do
    from(n in Node,
      where: n.parent_id == ^parent_id,
      select: coalesce(max(n.position) + 1, 0)
    )
  end

  @doc """
  Rebuilds paths for a node and all its descendants after a move operation.
  Returns a list of {node_id, new_path, new_depth} tuples.
  """
  def rebuild_paths(node, new_parent, descendants) do
    new_path = build_path(new_parent, node.id)
    new_depth = calculate_depth(new_parent)
    old_path_prefix = node.path

    updates = [{node.id, new_path, new_depth}]

    descendant_updates =
      Enum.map(descendants, fn desc ->
        # Replace old path prefix with new path prefix
        desc_new_path = String.replace_prefix(desc.path, old_path_prefix, new_path)
        depth_diff = new_depth - node.depth
        {desc.id, desc_new_path, desc.depth + depth_diff}
      end)

    updates ++ descendant_updates
  end

  @doc """
  Reorders siblings by updating positions.
  Takes a list of node IDs in the desired order and returns position updates.
  """
  def calculate_new_positions(node_ids) do
    node_ids
    |> Enum.with_index()
    |> Enum.map(fn {id, idx} -> {id, idx} end)
  end

  @doc """
  Builds a nested tree structure from a flat list of nodes.
  Assumes nodes are preloaded or have parent_id available.
  """
  def build_tree(nodes) do
    nodes_by_parent = Enum.group_by(nodes, & &1.parent_id)

    root_nodes = Map.get(nodes_by_parent, nil, [])

    Enum.map(root_nodes, fn root ->
      build_subtree(root, nodes_by_parent)
    end)
  end

  @doc """
  Builds a subtree starting from a given node.
  """
  def build_subtree(node, nodes_by_parent) do
    children = Map.get(nodes_by_parent, node.id, [])

    sorted_children =
      children
      # Sort by position first, then by id for consistent ordering when positions are equal
      |> Enum.sort_by(&{&1.position, &1.id})
      |> Enum.map(&build_subtree(&1, nodes_by_parent))

    Map.put(node, :children, sorted_children)
  end
end
