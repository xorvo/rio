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
    case Repo.one(from n in Node, where: is_nil(n.parent_id) and is_nil(n.deleted_at), order_by: n.id, limit: 1) do
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
  Excludes soft-deleted nodes.
  """
  def get_node!(id) do
    Node
    |> where([n], n.id == ^id and is_nil(n.deleted_at))
    |> Repo.one!()
  end

  @doc """
  Gets a single node by ID, returns nil if not found.
  Excludes soft-deleted nodes.
  """
  def get_node(id) do
    Node
    |> where([n], n.id == ^id and is_nil(n.deleted_at))
    |> Repo.one()
  end

  @doc """
  Gets a single node by ID, including soft-deleted nodes.
  Used internally for restoration operations.
  """
  def get_node_including_deleted!(id), do: Repo.get!(Node, id)

  @doc """
  Gets a node with its children preloaded.
  Excludes soft-deleted nodes.
  """
  def get_node_with_children!(id) do
    get_node!(id)
    |> Repo.preload(children: from(c in Node, where: is_nil(c.deleted_at), order_by: c.position))
  end

  @doc """
  Gets a node with attachments preloaded.
  Excludes soft-deleted nodes.
  """
  def get_node_with_attachments!(id) do
    get_node!(id)
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
      # Insert with empty path (will be updated after we have the ID)
      {:ok, node} =
        %Node{}
        |> Node.changeset(Map.merge(attrs, %{"path" => [], "position" => position, "depth" => 0}))
        |> Repo.insert()

      # Update with correct path (array containing just this node's ID)
      node
      |> Node.changeset(%{"path" => Tree.build_path(nil, node.id)})
      |> Repo.update!()
    end)
  end

  @doc """
  Creates a child node under a parent.
  """
  def create_child_node(parent_id, attrs) when is_binary(parent_id) do
    parent = get_node!(parent_id)
    create_child_node(parent, attrs)
  end

  def create_child_node(%Node{} = parent, attrs) do
    do_create_child_node(parent, attrs, &Node.changeset/2)
  end

  @doc """
  Creates a child node for inline editing (title can be empty initially).
  """
  def create_inline_child_node(parent_id, attrs) when is_binary(parent_id) do
    parent = get_node!(parent_id)
    create_inline_child_node(parent, attrs)
  end

  def create_inline_child_node(%Node{} = parent, attrs) do
    do_create_child_node(parent, attrs, &Node.inline_changeset/2)
  end

  defp do_create_child_node(%Node{} = parent, attrs, changeset_fn) do
    position = Repo.one(Tree.next_child_position(parent)) || 0
    depth = Tree.calculate_depth(parent)
    # Ensure consistent string keys to avoid mixed key errors
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      {:ok, node} =
        %Node{}
        |> changeset_fn.(Map.merge(attrs, %{
          "parent_id" => parent.id,
          "path" => [],
          "position" => position,
          "depth" => depth
        }))
        |> Repo.insert()

      node =
        node
        |> changeset_fn.(%{"path" => Tree.build_path(parent, node.id)})
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
  Hard deletes a node and all its descendants.
  Use soft_delete_node/1 for recoverable deletion.
  """
  def delete_node(%Node{} = node) do
    # Record deletion event before deleting
    Events.record_event(node, "deleted")
    Repo.delete(node)
  end

  @doc """
  Soft deletes a node and all its descendants.
  Returns {:ok, batch_id} where batch_id can be used for undo.
  Returns {:error, :locked, locked_nodes} if any nodes in the subtree are locked.
  """
  def soft_delete_node(%Node{} = node) do
    # Check if any nodes in subtree are locked
    descendants = Tree.descendants_query(node) |> Repo.all()
    all_nodes = [node | descendants]
    locked_nodes = Enum.filter(all_nodes, & &1.locked)

    if locked_nodes != [] do
      {:error, :locked, locked_nodes}
    else
      batch_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.transaction(fn ->
        all_node_ids = Enum.map(all_nodes, & &1.id)
        descendant_count = length(descendants)

        # Soft delete all nodes in the subtree
        from(n in Node, where: n.id in ^all_node_ids)
        |> Repo.update_all(set: [deleted_at: now, deletion_batch_id: batch_id])

        # Record deletion event for the root node
        Events.record_event(node, "soft_deleted", %{batch_id: batch_id, descendant_count: descendant_count})

        %{batch_id: batch_id, descendant_count: descendant_count}
      end)
    end
  end

  @doc """
  Soft deletes multiple nodes (batch operation).
  Each node and its descendants are deleted.
  Returns {:ok, batch_id}.
  Returns {:error, :locked, locked_nodes} if any nodes in the trees are locked.
  """
  def soft_delete_nodes(node_ids) when is_list(node_ids) do
    # Collect all nodes including descendants and check for locks
    all_nodes =
      Enum.flat_map(node_ids, fn node_id ->
        node = get_node!(node_id)
        descendants = Tree.descendants_query(node) |> Repo.all()
        [node | descendants]
      end)
      |> Enum.uniq_by(& &1.id)

    locked_nodes = Enum.filter(all_nodes, & &1.locked)

    if locked_nodes != [] do
      {:error, :locked, locked_nodes}
    else
      batch_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.transaction(fn ->
        all_ids = Enum.map(all_nodes, & &1.id)

        # Soft delete all
        from(n in Node, where: n.id in ^all_ids)
        |> Repo.update_all(set: [deleted_at: now, deletion_batch_id: batch_id])

        %{batch_id: batch_id, total_count: length(all_ids)}
      end)
    end
  end

  @doc """
  Restores all nodes in a deletion batch.
  Returns {:ok, count} with number of restored nodes.
  """
  def restore_deletion_batch(batch_id) do
    {count, _} =
      from(n in Node, where: n.deletion_batch_id == ^batch_id)
      |> Repo.update_all(set: [deleted_at: nil, deletion_batch_id: nil])

    {:ok, count}
  end

  # Archive operations

  @doc """
  Archives a node (only marks the root, subtree is implicitly hidden).
  Returns {:ok, %{batch_id, descendant_count}}.
  """
  def archive_node(%Node{} = node) do
    batch_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Count descendants for the undo message (but don't mark them as archived)
    descendant_count = count_descendants(node)

    Repo.transaction(fn ->
      # Only archive the root node - descendants are implicitly hidden
      from(n in Node, where: n.id == ^node.id)
      |> Repo.update_all(set: [archived_at: now, archive_batch_id: batch_id])

      Events.record_event(node, "archived", %{batch_id: batch_id, descendant_count: descendant_count})

      %{batch_id: batch_id, descendant_count: descendant_count}
    end)
  end

  @doc """
  Unarchives a node by clearing archived_at.
  """
  def unarchive_node(%Node{} = node) do
    result =
      node
      |> Node.changeset(%{archived_at: nil, archive_batch_id: nil})
      |> Repo.update()

    case result do
      {:ok, updated_node} ->
        Events.record_event(updated_node, "unarchived")
        {:ok, updated_node}

      error ->
        error
    end
  end

  @doc """
  Restores all nodes in an archive batch (undo operation).
  Returns {:ok, count} with number of restored nodes.
  """
  def restore_archive_batch(batch_id) do
    {count, _} =
      from(n in Node, where: n.archive_batch_id == ^batch_id)
      |> Repo.update_all(set: [archived_at: nil, archive_batch_id: nil])

    {:ok, count}
  end

  @doc """
  Gets completed todos that should be auto-archived (completed > N days ago).
  """
  def get_auto_archivable_todos(days_threshold \\ 7) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_threshold, :day)

    from(n in Node,
      where:
        n.is_todo == true and
          n.todo_completed == true and
          is_nil(n.archived_at) and
          is_nil(n.deleted_at) and
          not is_nil(n.completed_at) and
          n.completed_at < ^cutoff
    )
    |> Repo.all()
  end

  @doc """
  Batch archive multiple nodes (for auto-archive).
  Returns {:ok, %{batch_id, count}}.
  """
  def archive_nodes(nodes) when is_list(nodes) do
    if nodes == [] do
      {:ok, %{batch_id: nil, count: 0}}
    else
      batch_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.transaction(fn ->
        node_ids = Enum.map(nodes, & &1.id)

        from(n in Node, where: n.id in ^node_ids)
        |> Repo.update_all(set: [archived_at: now, archive_batch_id: batch_id])

        %{batch_id: batch_id, count: length(nodes)}
      end)
    end
  end

  @doc """
  Counts descendants of a node (excluding soft-deleted).
  """
  def count_descendants(%Node{} = node) do
    Tree.descendants_query(node)
    |> Repo.aggregate(:count)
  end

  @doc """
  Toggles the TODO completed state.
  """
  def toggle_todo(%Node{is_todo: true, todo_completed: completed} = node) do
    # Set completed_at when marking as complete, clear it when uncompleting
    completed_at = if completed, do: nil, else: DateTime.utc_now()

    result =
      node
      |> Node.changeset(%{todo_completed: !completed, completed_at: completed_at})
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
  Toggles the locked state of a node.
  """
  def toggle_lock(%Node{locked: locked} = node) do
    result =
      node
      |> Node.changeset(%{locked: !locked})
      |> Repo.update()

    case result do
      {:ok, updated_node} ->
        Events.record_event(updated_node, "lock_toggled")
        {:ok, updated_node}

      error ->
        error
    end
  end

  @doc """
  Gets the full subtree rooted at a node.
  Returns a nested structure.

  Options:
    - :show_archived - if true, includes archived nodes (default: false)
  """
  def get_subtree(node_or_id, opts \\ [])

  def get_subtree(node_id, opts) when is_binary(node_id) do
    root = get_node!(node_id)
    get_subtree(root, opts)
  end

  def get_subtree(%Node{} = root, opts) do
    show_archived = Keyword.get(opts, :show_archived, false)

    descendants =
      Tree.descendants_query(root)
      |> order_by([n], [n.depth, n.position])
      |> Repo.all()

    # Filter out archived subtrees unless show_archived is true
    filtered_descendants =
      if show_archived do
        descendants
      else
        filter_archived_subtrees(descendants)
      end

    all_nodes = [root | filtered_descendants]
    nodes_by_parent = Enum.group_by(all_nodes, & &1.parent_id)

    Tree.build_subtree(root, nodes_by_parent)
  end

  # Filter out nodes that are archived or whose ancestor is archived
  defp filter_archived_subtrees(nodes) do
    # Find all archived node IDs
    archived_ids =
      nodes
      |> Enum.filter(& &1.archived_at)
      |> MapSet.new(& &1.id)

    # Reject nodes that are archived or have an archived ancestor in their path
    Enum.reject(nodes, fn node ->
      node.archived_at != nil or
        Enum.any?(node.path, &MapSet.member?(archived_ids, &1))
    end)
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
  Excludes soft-deleted nodes.
  """
  def get_children(%Node{id: id}) do
    Node
    |> where([n], n.parent_id == ^id and is_nil(n.deleted_at))
    |> order_by([n], n.position)
    |> Repo.all()
  end

  def get_children(node_id) when is_binary(node_id) do
    Node
    |> where([n], n.parent_id == ^node_id and is_nil(n.deleted_at))
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
  Gets all nodes in the database (for global search).
  Excludes soft-deleted nodes.
  """
  def get_all_nodes do
    Node
    |> where([n], is_nil(n.deleted_at))
    |> order_by([n], [n.depth, n.path, n.position])
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
