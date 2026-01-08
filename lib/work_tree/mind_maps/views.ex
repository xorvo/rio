defmodule WorkTree.MindMaps.Views do
  @moduledoc """
  Pre-built view queries for common filtered views.
  Includes TODO views with grouping and priority sorting.
  """

  import Ecto.Query
  alias WorkTree.Repo
  alias WorkTree.MindMaps.Node

  @doc """
  Get all TODO items sorted by priority (p0 first) then by updated date.

  Options:
  - `:include_completed` - Include completed todos (default: false)
  - `:limit` - Maximum results (default: 100)
  - `:parent_id` - Filter to todos under a specific parent (optional)
  """
  def list_todos(opts \\ []) do
    include_completed = Keyword.get(opts, :include_completed, false)
    limit = Keyword.get(opts, :limit, 100)
    parent_id = Keyword.get(opts, :parent_id)

    query =
      Node
      |> where([n], n.is_todo == true)
      |> limit(^limit)
      # Sort by priority (NULL last), then by updated_at desc
      |> order_by([n], asc_nulls_last: n.priority, desc: n.updated_at)

    query =
      if include_completed do
        query
      else
        where(query, [n], n.todo_completed == false)
      end

    query =
      if parent_id do
        # Filter to descendants of the given parent using array containment
        # Cast to Ecto.UUID for proper binary encoding
        where(query, [n], type(^parent_id, Ecto.UUID) == fragment("ANY(?)", n.path))
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Get TODO items grouped by their immediate parent (or root if no parent).
  Returns a map of %{parent_id => [todos]}.

  Useful for showing todos with context.
  """
  def list_todos_grouped_by_parent(opts \\ []) do
    todos = list_todos(opts)

    todos
    |> Enum.group_by(& &1.parent_id)
  end

  @doc """
  Get TODO items with their parent path for context.
  Returns list of {node, ancestor_titles} tuples.
  """
  def list_todos_with_context(opts \\ []) do
    todos = list_todos(opts)

    Enum.map(todos, fn todo ->
      ancestor_titles = get_ancestor_titles(todo)
      {todo, ancestor_titles}
    end)
  end

  @doc """
  Get TODO items grouped by priority level.
  Returns a map of %{priority => [todos]}.
  Nodes without priority are grouped under :unset.
  """
  def list_todos_by_priority(opts \\ []) do
    todos = list_todos(opts)

    todos
    |> Enum.group_by(fn node ->
      node.priority || :unset
    end)
    |> Enum.sort_by(fn
      # Put unset at the end
      {:unset, _} -> {1, 999}
      # Sort by priority number
      {priority, _} -> {0, priority}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Get high-priority TODO items (p0-p2).
  """
  def list_urgent_todos(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Node
    |> where([n], n.is_todo == true and n.todo_completed == false)
    |> where([n], n.priority <= 2)
    |> order_by([n], asc: n.priority, desc: n.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get recently modified nodes.

  Options:
  - `:limit` - Maximum results (default: 20)
  - `:since` - Only nodes modified after this datetime (optional)
  """
  def list_recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    since = Keyword.get(opts, :since)

    query =
      Node
      |> order_by([n], desc: n.updated_at)
      |> limit(^limit)

    query =
      if since do
        where(query, [n], n.updated_at >= ^since)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Get nodes at a specific depth level.
  Useful for getting all top-level items, etc.
  """
  def list_at_depth(depth, opts \\ []) when is_integer(depth) do
    limit = Keyword.get(opts, :limit, 100)

    Node
    |> where([n], n.depth == ^depth)
    |> order_by([n], asc: n.position, asc: n.id)
    |> limit(^limit)
    |> Repo.all()
  end

  # Private helpers

  defp get_ancestor_titles(%Node{path: path}) do
    # Path is already a UUID array, just drop self (last element)
    ancestor_ids = Enum.drop(path, -1)

    if ancestor_ids == [] do
      []
    else
      Node
      |> where([n], n.id in ^ancestor_ids)
      |> select([n], {n.id, n.title})
      |> Repo.all()
      |> Map.new()
      |> then(fn title_map ->
        Enum.map(ancestor_ids, fn id -> title_map[id] || "Unknown" end)
      end)
    end
  end
end
