defmodule Rio.MindMaps.Tree do
  @moduledoc """
  Handles tree path operations for the mind map node hierarchy.
  Uses materialized path pattern with delimited strings for efficient subtree queries.
  """

  import Ecto.Query
  alias Rio.MindMaps.Node

  @doc """
  Builds the path for a new node given its parent and the node's own ID.
  Root nodes have path as single-element array with their ID.
  """
  def build_path(nil, node_id), do: [node_id]
  def build_path(%Node{path: parent_path}, node_id), do: parent_path ++ [node_id]

  @doc """
  Calculates depth based on parent.
  """
  def calculate_depth(nil), do: 0
  def calculate_depth(%Node{depth: parent_depth}), do: parent_depth + 1

  @doc """
  Returns a query for all descendants of a node (subtree).
  Uses LIKE on delimited string path.
  Excludes soft-deleted nodes by default.
  """
  def descendants_query(%Node{id: id}, opts \\ []) do
    include_deleted = Keyword.get(opts, :include_deleted, false)
    pattern = "%/#{id}/%"

    query =
      from(n in Node,
        where: like(n.path, ^pattern) and n.id != ^id
      )

    if include_deleted do
      query
    else
      from(n in query, where: is_nil(n.deleted_at))
    end
  end

  @doc """
  Returns a query for all ancestors of a node.
  Path is already a list of UUIDs, just drop the last element (self).
  Excludes soft-deleted nodes.
  """
  def ancestors_query(%Node{path: path}) do
    ancestor_ids = Enum.drop(path, -1)

    from(n in Node, where: n.id in ^ancestor_ids and is_nil(n.deleted_at), order_by: n.depth)
  end

  @doc """
  Returns a query for siblings of a node (nodes with same parent).
  Excludes soft-deleted nodes.
  """
  def siblings_query(%Node{parent_id: parent_id, id: id}) do
    from(n in Node,
      where: n.parent_id == ^parent_id and n.id != ^id and is_nil(n.deleted_at),
      order_by: n.position
    )
  end

  @doc """
  Returns the next position for a new child under a parent.
  Uses max(position) + 1 to avoid duplicate positions after deletions.
  Only considers non-deleted nodes.
  """
  def next_child_position(nil) do
    # For root nodes, get max position + 1
    from(n in Node,
      where: is_nil(n.parent_id) and is_nil(n.deleted_at),
      select: coalesce(max(n.position) + 1, 0)
    )
  end

  def next_child_position(%Node{id: parent_id}) do
    from(n in Node,
      where: n.parent_id == ^parent_id and is_nil(n.deleted_at),
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
    old_path = node.path

    updates = [{node.id, new_path, new_depth}]

    descendant_updates =
      Enum.map(descendants, fn desc ->
        # Replace old path prefix with new path prefix
        # Old path was [a, b, c, node.id, ...], new path replaces [a, b, c, node.id] with new_path
        old_path_length = length(old_path)
        desc_suffix = Enum.drop(desc.path, old_path_length)
        desc_new_path = new_path ++ desc_suffix
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
      |> sort_siblings()
      |> Enum.map(&build_subtree(&1, nodes_by_parent))

    Map.put(node, :children, sorted_children)
  end

  @doc """
  Returns the sort key for a node.
  Used for consistent ordering across the application.
  Priority first (nil treated as lowest), then position, then id.
  """
  def sort_key(node) do
    {priority_sort_key(node.priority), node.position, node.id}
  end

  @doc """
  Sorts a list of nodes by priority, position, then id.
  This is the canonical sorting order used throughout the app.
  """
  def sort_siblings(nodes) do
    Enum.sort_by(nodes, &sort_key/1)
  end

  @doc """
  Compares two sibling nodes.
  Returns :lt, :eq, or :gt based on the canonical sort order.
  """
  def compare_siblings(node_a, node_b) do
    key_a = sort_key(node_a)
    key_b = sort_key(node_b)

    cond do
      key_a < key_b -> :lt
      key_a > key_b -> :gt
      true -> :eq
    end
  end

  # Priority sort key: nil becomes infinity (999), otherwise use the actual priority value
  # Lower priority number = higher priority (P0 > P1 > P2 > P3 > nil)
  defp priority_sort_key(nil), do: 999
  defp priority_sort_key(priority), do: priority
end
