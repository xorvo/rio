defmodule WorkTree.MindMaps.Search do
  @moduledoc """
  Search functionality for nodes using PostgreSQL trigram similarity.
  Supports fuzzy search on titles and body content.
  """

  import Ecto.Query
  alias WorkTree.Repo
  alias WorkTree.MindMaps.Node

  @doc """
  Search nodes by title using trigram similarity.
  Returns nodes sorted by similarity score (best matches first).

  Options:
  - `:limit` - Maximum number of results (default: 20)
  - `:threshold` - Minimum similarity score 0.0-1.0 (default: 0.1)
  """
  def search_by_title(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 20)
    threshold = Keyword.get(opts, :threshold, 0.1)

    query_string = sanitize_query(query)

    if String.trim(query_string) == "" do
      []
    else
      sql = """
      SELECT n.*, similarity(n.title, $1) AS sim_score
      FROM nodes n
      WHERE similarity(n.title, $1) > $2
      ORDER BY sim_score DESC
      LIMIT $3
      """

      result = Repo.query!(sql, [query_string, threshold, limit])

      columns = Enum.map(result.columns, &String.to_atom/1)

      Enum.map(result.rows, fn row ->
        map = Enum.zip(columns, row) |> Map.new()
        struct_from_map(map)
      end)
    end
  end

  @doc """
  Search nodes containing text in title or body content.
  Uses ILIKE for case-insensitive substring matching.
  """
  def search_contains(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 20)
    query_string = "%#{sanitize_query(query)}%"

    if String.trim(query) == "" do
      []
    else
      Node
      |> where([n], ilike(n.title, ^query_string))
      |> or_where([n], fragment("?->>'content' ILIKE ?", n.body, ^query_string))
      |> limit(^limit)
      |> order_by([n], desc: n.updated_at)
      |> Repo.all()
    end
  end

  @doc """
  Search for TODO items by title.
  """
  def search_todos(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 20)
    include_completed = Keyword.get(opts, :include_completed, true)

    base_query =
      Node
      |> where([n], n.is_todo == true)
      |> limit(^limit)
      |> order_by([n], asc: n.priority, desc: n.updated_at)

    base_query =
      if include_completed do
        base_query
      else
        where(base_query, [n], n.todo_completed == false)
      end

    if String.trim(query) == "" do
      Repo.all(base_query)
    else
      query_string = "%#{sanitize_query(query)}%"

      base_query
      |> where([n], ilike(n.title, ^query_string))
      |> Repo.all()
    end
  end

  # Sanitize search query to prevent SQL injection
  defp sanitize_query(query) do
    query
    |> String.replace(~r/[%_\\]/, fn
      "%" -> "\\%"
      "_" -> "\\_"
      "\\" -> "\\\\"
    end)
  end

  # Convert a raw SQL result map to a Node struct
  defp struct_from_map(map) do
    %Node{
      id: map[:id],
      title: map[:title],
      body: map[:body],
      is_todo: map[:is_todo],
      todo_completed: map[:todo_completed],
      priority: map[:priority],
      path: map[:path],
      position: map[:position],
      depth: map[:depth],
      edge_label: map[:edge_label],
      parent_id: map[:parent_id],
      inserted_at: map[:inserted_at],
      updated_at: map[:updated_at]
    }
  end
end
