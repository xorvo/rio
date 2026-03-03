defmodule WorkTree.MindMaps.Search do
  @moduledoc """
  Search functionality for nodes.
  Uses FTS5 for content search, LIKE + FuzzySearch for title matching.
  """

  import Ecto.Query
  alias WorkTree.Repo
  alias WorkTree.MindMaps.Node

  @doc """
  Search nodes by title using LIKE + FuzzySearch.
  Returns nodes sorted by relevance score (best matches first).

  Options:
  - `:limit` - Maximum number of results (default: 20)
  """
  def search_by_title(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 20)

    query_string = sanitize_query(query)

    if String.trim(query_string) == "" do
      []
    else
      search_by_title_impl(query_string, limit)
    end
  end

  defp search_by_title_impl(query_string, limit) do
    # Tier 1: FTS5 prefix/word matching for fast indexed search
    fts_query = build_fts_query(query_string) <> "*"

    fts_results =
      try do
        search_title_fts(fts_query, limit)
      rescue
        _ -> []
      end

    if length(fts_results) >= limit do
      fts_results
    else
      # Tier 2: LIKE + FuzzySearch with Jaro-Winkler for broader matching
      like_pattern = "%#{query_string}%"

      candidates =
        Node
        |> where([n], is_nil(n.deleted_at))
        |> where([n], like(n.title, ^like_pattern))
        |> limit(^(limit * 3))
        |> order_by([n], desc: n.updated_at)
        |> Repo.all()

      # If LIKE found few results, also grab all nodes for fuzzy matching
      candidates =
        if length(candidates) < limit do
          all =
            Node
            |> where([n], is_nil(n.deleted_at))
            |> Repo.all()

          (candidates ++ all) |> Enum.uniq_by(& &1.id)
        else
          candidates
        end

      fuzzy_results =
        candidates
        |> WorkTree.FuzzySearch.search(query_string)
        |> Enum.map(fn {node, _score, _highlights, _ancestry} -> node end)

      # Merge FTS and fuzzy results, deduplicate
      fts_ids = MapSet.new(fts_results, & &1.id)

      additional =
        Enum.reject(fuzzy_results, fn node -> MapSet.member?(fts_ids, node.id) end)

      Enum.take(fts_results ++ additional, limit)
    end
  end

  defp search_title_fts(fts_query, limit) do
    sql = """
    SELECT n.* FROM nodes n
    JOIN nodes_fts fts ON fts.rowid = n.rowid
    WHERE nodes_fts MATCH ?1
      AND n.deleted_at IS NULL
    ORDER BY fts.rank
    LIMIT ?2
    """

    result = Repo.query!(sql, [fts_query, limit])
    rows_to_nodes(result)
  end

  @doc """
  Search nodes containing text in title or body content.
  Uses FTS5 MATCH for fast indexed full-text search, with LIKE fallback.
  """
  def search_contains(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 20)

    if String.trim(query) == "" do
      []
    else
      fts_query = build_fts_query(query)
      fts_results = search_contains_fts(fts_query, limit)

      # If FTS found enough results, return them
      if length(fts_results) >= limit do
        fts_results
      else
        # Fall back to LIKE for partial matches FTS might miss
        like_query = "%#{sanitize_query(query)}%"
        like_results = search_contains_like(like_query, limit)

        # Merge and deduplicate, FTS results first (better ranked)
        fts_ids = MapSet.new(fts_results, & &1.id)

        additional =
          Enum.reject(like_results, fn node -> MapSet.member?(fts_ids, node.id) end)

        Enum.take(fts_results ++ additional, limit)
      end
    end
  end

  defp search_contains_fts(fts_query, limit) do
    sql = """
    SELECT n.* FROM nodes n
    JOIN nodes_fts fts ON fts.rowid = n.rowid
    WHERE nodes_fts MATCH ?1
      AND n.deleted_at IS NULL
    ORDER BY fts.rank
    LIMIT ?2
    """

    result = Repo.query!(sql, [fts_query, limit])
    rows_to_nodes(result)
  end

  defp search_contains_like(like_query, limit) do
    Node
    |> where([n], is_nil(n.deleted_at))
    |> where(
      [n],
      like(n.title, ^like_query) or
        like(fragment("json_extract(?, '$.content')", n.body), ^like_query)
    )
    |> limit(^limit)
    |> order_by([n], desc: n.updated_at)
    |> Repo.all()
  end

  @doc """
  Search for TODO items by title.
  """
  def search_todos(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 20)
    include_completed = Keyword.get(opts, :include_completed, true)

    base_query =
      Node
      |> where([n], n.is_todo == true and is_nil(n.deleted_at))
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
      |> where([n], like(n.title, ^query_string))
      |> Repo.all()
    end
  end

  # Build an FTS5 query string from user input.
  # Wraps each word in quotes to handle special characters,
  # and joins with implicit AND.
  defp build_fts_query(query) do
    query
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(fn word -> "\"#{String.replace(word, "\"", "")}\"" end)
    |> Enum.join(" ")
  end

  # Sanitize search query to prevent SQL injection in LIKE patterns
  defp sanitize_query(query) do
    query
    |> String.replace(~r/[%_\\]/, fn
      "%" -> "\\%"
      "_" -> "\\_"
      "\\" -> "\\\\"
    end)
  end

  # Convert raw SQL result rows to Node structs
  defp rows_to_nodes(%{columns: columns, rows: rows}) do
    fields = Enum.map(columns, &String.to_existing_atom/1)

    Enum.map(rows, fn row ->
      attrs = Enum.zip(fields, row) |> Map.new()

      %Node{
        id: attrs[:id],
        title: attrs[:title],
        body: attrs[:body],
        is_todo: attrs[:is_todo],
        todo_completed: attrs[:todo_completed],
        priority: attrs[:priority],
        path: WorkTree.Ecto.PathType.deserialize_path(attrs[:path]),
        position: attrs[:position],
        depth: attrs[:depth],
        edge_label: attrs[:edge_label],
        parent_id: attrs[:parent_id],
        link: attrs[:link],
        due_date: attrs[:due_date],
        locked: attrs[:locked],
        deleted_at: attrs[:deleted_at],
        inserted_at: attrs[:inserted_at],
        updated_at: attrs[:updated_at]
      }
    end)
  end
end
