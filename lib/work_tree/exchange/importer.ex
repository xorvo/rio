defmodule WorkTree.Exchange.Importer do
  @moduledoc """
  Imports WTXF data into the SQLite database.

  Supports two modes:
    - `:full` — Wipe all tables and insert everything fresh
    - `:merge` — Insert new nodes by UUID, LWW on conflicts by `updated_at`
  """

  import Ecto.Query
  alias WorkTree.Repo
  alias WorkTree.MindMaps.{Node, Attachment}
  alias WorkTree.Events.NodeEvent
  alias WorkTree.Exchange.{Format, Conflict}

  require Logger

  @doc """
  Imports a validated WTXF data map into the database.

  Options:
    - `:mode` - `:full` (default) or `:merge`

  Returns `{:ok, stats}` or `{:error, reason}`.
  """
  def import_data(data, opts \\ []) do
    mode = Keyword.get(opts, :mode, :full)

    nodes = Enum.map(data["nodes"] || [], &Format.deserialize_node/1)
    attachments = Enum.map(data["attachments"] || [], &Format.deserialize_attachment/1)
    events = Enum.map(data["events"] || [], &Format.deserialize_event/1)

    # Sort nodes topologically: parents before children (by depth)
    sorted_nodes = Enum.sort_by(nodes, & &1.depth)

    case mode do
      :full -> full_restore(sorted_nodes, attachments, events)
      :merge -> merge_import(sorted_nodes, attachments, events)
    end
  end

  # --- Full Restore ---

  defp full_restore(nodes, attachments, events) do
    Repo.transaction(fn ->
      truncate_tables()
      node_count = insert_nodes(nodes)
      attachment_count = insert_attachments(attachments)
      event_count = insert_events(events)
      verify_paths(nodes)
      rebuild_fts()

      %{
        mode: :full,
        nodes_imported: node_count,
        attachments_imported: attachment_count,
        events_imported: event_count,
        conflicts: []
      }
    end)
  end

  defp truncate_tables do
    Repo.query!("DELETE FROM node_events")
    Repo.query!("DELETE FROM attachments")
    Repo.query!("DELETE FROM nodes")
  end

  # --- Merge Import ---

  defp merge_import(nodes, attachments, events) do
    Repo.transaction(fn ->
      # Build a set of existing node IDs for conflict detection
      existing_ids = existing_node_ids()

      {node_count, conflicts} = merge_nodes(nodes, existing_ids)
      attachment_count = merge_attachments(attachments)
      event_count = merge_events(events)
      verify_paths(nodes)
      rebuild_fts()

      %{
        mode: :merge,
        nodes_imported: node_count,
        attachments_imported: attachment_count,
        events_imported: event_count,
        conflicts: conflicts
      }
    end)
  end

  defp existing_node_ids do
    Node
    |> select([n], n.id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp merge_nodes(nodes, existing_ids) do
    Enum.reduce(nodes, {0, []}, fn attrs, {count, conflicts} ->
      if MapSet.member?(existing_ids, attrs.id) do
        local_node = Repo.get!(Node, attrs.id)
        resolution = Conflict.resolve_node(local_node, attrs)

        case resolution do
          :keep_remote ->
            update_node_raw(local_node, attrs)

            conflict =
              Conflict.build_conflict(
                attrs.id,
                "edit_vs_edit",
                local_node.updated_at,
                attrs.updated_at,
                :keep_remote
              )

            {count + 1, [conflict | conflicts]}

          :keep_local ->
            conflict =
              Conflict.build_conflict(
                attrs.id,
                "edit_vs_edit",
                local_node.updated_at,
                attrs.updated_at,
                :keep_local
              )

            {count, [conflict | conflicts]}

          :skip ->
            {count, conflicts}
        end
      else
        insert_node_raw(attrs)
        {count + 1, conflicts}
      end
    end)
  end

  defp merge_attachments(attachments) do
    existing_ids =
      Attachment
      |> select([a], a.id)
      |> Repo.all()
      |> MapSet.new()

    Enum.reduce(attachments, 0, fn attrs, count ->
      if MapSet.member?(existing_ids, attrs.id) do
        count
      else
        insert_attachment_raw(attrs)
        count + 1
      end
    end)
  end

  defp merge_events(events) do
    existing_ids =
      NodeEvent
      |> select([e], e.id)
      |> Repo.all()
      |> MapSet.new()

    Enum.reduce(events, 0, fn attrs, count ->
      if MapSet.member?(existing_ids, attrs.id) do
        count
      else
        insert_event_raw(attrs)
        count + 1
      end
    end)
  end

  # --- Raw Insert/Update (bypass changesets for import) ---

  defp insert_nodes(nodes) do
    Enum.each(nodes, &insert_node_raw/1)
    length(nodes)
  end

  defp insert_attachments(attachments) do
    Enum.each(attachments, &insert_attachment_raw/1)
    length(attachments)
  end

  defp insert_events(events) do
    Enum.each(events, &insert_event_raw/1)
    length(events)
  end

  defp insert_node_raw(attrs) do
    now = attrs.inserted_at || DateTime.utc_now() |> DateTime.truncate(:second)
    path = WorkTree.Ecto.PathType.serialize_path(attrs.path || [])

    Repo.query!(
      """
      INSERT INTO nodes (
        id, title, body, is_todo, todo_completed, path, position, depth,
        edge_label, parent_id, priority, link, due_date, completed_at,
        locked, deleted_at, deletion_batch_id, archived_at, archive_batch_id,
        inserted_at, updated_at
      ) VALUES (
        ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14,
        ?15, ?16, ?17, ?18, ?19, ?20, ?21
      )
      """,
      [
        attrs.id,
        attrs.title,
        Jason.encode!(attrs.body || %{}),
        bool_to_int(attrs.is_todo),
        bool_to_int(attrs.todo_completed),
        path,
        attrs.position,
        attrs.depth,
        attrs.edge_label,
        attrs.parent_id,
        attrs.priority,
        attrs.link,
        format_date(attrs.due_date),
        format_datetime(attrs.completed_at),
        bool_to_int(attrs.locked),
        format_datetime(attrs.deleted_at),
        attrs.deletion_batch_id,
        format_datetime(attrs.archived_at),
        attrs.archive_batch_id,
        format_datetime(now),
        format_datetime(attrs.updated_at || now)
      ]
    )
  end

  defp update_node_raw(existing, attrs) do
    path = WorkTree.Ecto.PathType.serialize_path(attrs.path || [])

    Repo.query!(
      """
      UPDATE nodes SET
        title = ?2, body = ?3, is_todo = ?4, todo_completed = ?5,
        path = ?6, position = ?7, depth = ?8, edge_label = ?9,
        parent_id = ?10, priority = ?11, link = ?12, due_date = ?13,
        completed_at = ?14, locked = ?15, deleted_at = ?16,
        deletion_batch_id = ?17, archived_at = ?18, archive_batch_id = ?19,
        updated_at = ?20
      WHERE id = ?1
      """,
      [
        existing.id,
        attrs.title,
        Jason.encode!(attrs.body || %{}),
        bool_to_int(attrs.is_todo),
        bool_to_int(attrs.todo_completed),
        path,
        attrs.position,
        attrs.depth,
        attrs.edge_label,
        attrs.parent_id,
        attrs.priority,
        attrs.link,
        format_date(attrs.due_date),
        format_datetime(attrs.completed_at),
        bool_to_int(attrs.locked),
        format_datetime(attrs.deleted_at),
        attrs.deletion_batch_id,
        format_datetime(attrs.archived_at),
        attrs.archive_batch_id,
        format_datetime(attrs.updated_at)
      ]
    )
  end

  defp insert_attachment_raw(attrs) do
    now = attrs.inserted_at || DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.query!(
      """
      INSERT INTO attachments (
        id, node_id, type, url, file_path, title, metadata, position,
        inserted_at, updated_at
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
      """,
      [
        attrs.id,
        attrs.node_id,
        attrs.type,
        attrs.url,
        attrs.file_path,
        attrs.title,
        Jason.encode!(attrs.metadata || %{}),
        attrs.position,
        format_datetime(now),
        format_datetime(attrs.updated_at || now)
      ]
    )
  end

  defp insert_event_raw(attrs) do
    now = attrs.inserted_at || DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.query!(
      """
      INSERT INTO node_events (
        id, node_id, event_type, snapshot, metadata, inserted_at
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
      """,
      [
        attrs.id,
        attrs.node_id,
        attrs.event_type,
        Jason.encode!(attrs.snapshot || %{}),
        Jason.encode!(attrs.metadata || %{}),
        format_datetime(now)
      ]
    )
  end

  # --- Post-Import: Path Verification ---

  defp verify_paths(imported_nodes) do
    # Build a parent lookup from imported data
    nodes_by_id =
      imported_nodes
      |> Enum.map(&{&1.id, &1})
      |> Map.new()

    # Walk from roots and verify paths
    roots = Enum.filter(imported_nodes, &is_nil(&1.parent_id))

    Enum.each(roots, fn root ->
      verify_subtree(root, [], 0, nodes_by_id)
    end)
  end

  defp verify_subtree(node, expected_path, expected_depth, nodes_by_id) do
    actual_path = expected_path ++ [node.id]

    if node.path != actual_path or node.depth != expected_depth do
      path_str = WorkTree.Ecto.PathType.serialize_path(actual_path)

      Repo.query!(
        "UPDATE nodes SET path = ?1, depth = ?2 WHERE id = ?3",
        [path_str, expected_depth, node.id]
      )

      Logger.debug("Fixed path for node #{node.id}: depth=#{expected_depth}")
    end

    # Find children of this node
    children =
      nodes_by_id
      |> Map.values()
      |> Enum.filter(&(&1.parent_id == node.id))
      |> Enum.sort_by(& &1.position)

    Enum.each(children, fn child ->
      verify_subtree(child, actual_path, expected_depth + 1, nodes_by_id)
    end)
  end

  # --- Post-Import: FTS5 Rebuild ---

  defp rebuild_fts do
    Repo.query!("DELETE FROM nodes_fts")

    Repo.query!("""
    INSERT INTO nodes_fts(rowid, title, body_text)
      SELECT rowid, title, json_extract(body, '$.content') FROM nodes
    """)
  end

  # --- Helpers ---

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
  defp bool_to_int(nil), do: 0

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = dt) do
    dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp format_datetime(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp format_date(nil), do: nil
  defp format_date(%Date{} = d), do: Date.to_iso8601(d)
end
