defmodule WorkTree.MindMaps do
  @moduledoc """
  Context module for mind map operations.
  Manages nodes, attachments, and tree structure.
  """

  import Ecto.Query
  alias WorkTree.Repo
  alias WorkTree.MindMaps.{Node, Attachment, Tree}
  alias WorkTree.Events

  # Node CRUD

  @doc """
  Gets or creates the single global root node.
  This is the entry point for the entire mind map tree.
  """
  def get_or_create_global_root do
    case Repo.one(from n in Node, where: is_nil(n.parent_id), order_by: n.id, limit: 1) do
      nil ->
        {:ok, root} = create_root_node(%{"title" => "Mind Map"})
        root

      root ->
        root
    end
  end

  @doc """
  Gets a single node by ID.
  Raises `Ecto.NoResultsError` if not found.
  """
  def get_node!(id), do: Repo.get!(Node, id)

  @doc """
  Gets a single node by ID, returns nil if not found.
  """
  def get_node(id), do: Repo.get(Node, id)

  @doc """
  Gets a node with its children preloaded.
  """
  def get_node_with_children!(id) do
    Node
    |> Repo.get!(id)
    |> Repo.preload(children: from(c in Node, order_by: c.position))
  end

  @doc """
  Gets a node with attachments preloaded.
  """
  def get_node_with_attachments!(id) do
    Node
    |> Repo.get!(id)
    |> Repo.preload(attachments: from(a in Attachment, order_by: a.position))
  end

  @doc """
  Creates a new root node (no parent).
  """
  def create_root_node(attrs) do
    position = Repo.one(Tree.next_child_position(nil)) || 0
    # Ensure consistent string keys to avoid mixed key errors
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      # Insert with temporary path
      {:ok, node} =
        %Node{}
        |> Node.changeset(Map.merge(attrs, %{"path" => "temp", "position" => position, "depth" => 0}))
        |> Repo.insert()

      # Update with correct path
      node
      |> Node.changeset(%{"path" => Tree.build_path(nil, node.id)})
      |> Repo.update!()
    end)
  end

  @doc """
  Creates a child node under a parent.
  """
  def create_child_node(parent_id, attrs) when is_integer(parent_id) do
    parent = get_node!(parent_id)
    create_child_node(parent, attrs)
  end

  def create_child_node(%Node{} = parent, attrs) do
    position = Repo.one(Tree.next_child_position(parent)) || 0
    depth = Tree.calculate_depth(parent)
    # Ensure consistent string keys to avoid mixed key errors
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      {:ok, node} =
        %Node{}
        |> Node.changeset(Map.merge(attrs, %{
          "parent_id" => parent.id,
          "path" => "temp",
          "position" => position,
          "depth" => depth
        }))
        |> Repo.insert()

      node =
        node
        |> Node.changeset(%{"path" => Tree.build_path(parent, node.id)})
        |> Repo.update!()

      # Record creation event
      Events.record_event(node, "created")

      node
    end)
  end

  @doc """
  Creates a sibling node (same parent as the given node).
  """
  def create_sibling_node(%Node{parent_id: nil} = _node, attrs) do
    create_root_node(attrs)
  end

  def create_sibling_node(%Node{parent_id: parent_id}, attrs) do
    create_child_node(parent_id, attrs)
  end

  @doc """
  Updates a node.
  """
  def update_node(%Node{} = node, attrs) do
    result =
      node
      |> Node.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_node} ->
        Events.record_event(updated_node, "updated")
        {:ok, updated_node}

      error ->
        error
    end
  end

  @doc """
  Deletes a node and all its descendants.
  """
  def delete_node(%Node{} = node) do
    # Record deletion event before deleting
    Events.record_event(node, "deleted")
    Repo.delete(node)
  end

  @doc """
  Toggles the TODO completed state.
  """
  def toggle_todo(%Node{is_todo: true, todo_completed: completed} = node) do
    result =
      node
      |> Node.changeset(%{todo_completed: !completed})
      |> Repo.update()

    case result do
      {:ok, updated_node} ->
        Events.record_event(updated_node, "todo_toggled")
        {:ok, updated_node}

      error ->
        error
    end
  end

  def toggle_todo(%Node{} = node), do: {:ok, node}

  @doc """
  Gets the full subtree rooted at a node.
  Returns a nested structure.
  """
  def get_subtree(node_id) when is_integer(node_id) do
    root = get_node!(node_id)
    get_subtree(root)
  end

  def get_subtree(%Node{} = root) do
    descendants =
      Tree.descendants_query(root)
      |> order_by([n], [n.depth, n.position])
      |> Repo.all()

    all_nodes = [root | descendants]
    nodes_by_parent = Enum.group_by(all_nodes, & &1.parent_id)

    Tree.build_subtree(root, nodes_by_parent)
  end

  @doc """
  Gets ancestors of a node (path to root).
  """
  def get_ancestors(%Node{} = node) do
    Tree.ancestors_query(node)
    |> Repo.all()
  end

  @doc """
  Gets children of a node.
  """
  def get_children(%Node{id: id}) do
    Node
    |> where([n], n.parent_id == ^id)
    |> order_by([n], n.position)
    |> Repo.all()
  end

  def get_children(node_id) when is_integer(node_id) do
    Node
    |> where([n], n.parent_id == ^node_id)
    |> order_by([n], n.position)
    |> Repo.all()
  end

  @doc """
  Gets siblings of a node.
  """
  def get_siblings(%Node{} = node) do
    Tree.siblings_query(node)
    |> Repo.all()
  end

  @doc """
  Reorders children of a parent node.
  Takes a list of node IDs in the desired order.
  """
  def reorder_children(node_ids) when is_list(node_ids) do
    Repo.transaction(fn ->
      node_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, position} ->
        from(n in Node, where: n.id == ^id)
        |> Repo.update_all(set: [position: position])
      end)
    end)
  end

  @doc """
  Moves a node to a new parent at a specific position.
  """
  def move_node(%Node{} = node, new_parent_id, new_position) do
    new_parent = if new_parent_id, do: get_node!(new_parent_id), else: nil

    Repo.transaction(fn ->
      descendants =
        Tree.descendants_query(node)
        |> Repo.all()

      path_updates = Tree.rebuild_paths(node, new_parent, descendants)

      Enum.each(path_updates, fn {id, new_path, new_depth} ->
        from(n in Node, where: n.id == ^id)
        |> Repo.update_all(set: [path: new_path, depth: new_depth])
      end)

      from(n in Node, where: n.id == ^node.id)
      |> Repo.update_all(set: [parent_id: new_parent_id, position: new_position])

      get_node!(node.id)
    end)
  end

  # Attachment operations

  @doc """
  Adds an attachment to a node.
  """
  def add_attachment(%Node{id: node_id}, attrs) do
    position =
      Repo.one(
        from(a in Attachment,
          where: a.node_id == ^node_id,
          select: count(a.id)
        )
      ) || 0

    %Attachment{}
    |> Attachment.changeset(Map.merge(attrs, %{node_id: node_id, position: position}))
    |> Repo.insert()
  end

  @doc """
  Updates an attachment.
  """
  def update_attachment(%Attachment{} = attachment, attrs) do
    attachment
    |> Attachment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an attachment.
  """
  def delete_attachment(%Attachment{} = attachment) do
    Repo.delete(attachment)
  end

  @doc """
  Gets attachments for a node.
  """
  def list_attachments(node_id) do
    Attachment
    |> where([a], a.node_id == ^node_id)
    |> order_by([a], a.position)
    |> Repo.all()
  end

  # Change functions for LiveView forms

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking node changes.
  """
  def change_node(%Node{} = node, attrs \\ %{}) do
    Node.changeset(node, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking attachment changes.
  """
  def change_attachment(%Attachment{} = attachment, attrs \\ %{}) do
    Attachment.changeset(attachment, attrs)
  end

  # Private helpers

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
