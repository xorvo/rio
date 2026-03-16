defmodule Rio.Sync.Merger do
  @moduledoc """
  Applies remote changeset operations with conflict resolution.

  Routes each operation to the appropriate conflict resolution strategy
  and records conflicts for user review.
  """

  alias Rio.Repo
  alias Rio.MindMaps.Node
  alias Rio.Exchange.Format
  alias Rio.Sync.Strategies.{LastWriterWins, EditWinsOverDelete, TreeConflict}

  require Logger

  @doc """
  Applies a list of changes from a remote changeset.
  Returns `{:ok, %{applied: count, conflicts: [conflict]}}`.
  """
  def apply_changes(changes) do
    Repo.transaction(fn ->
      results = Enum.map(changes, &apply_change/1)

      applied = Enum.count(results, &match?({:applied, _}, &1))
      conflicts = results |> Enum.flat_map(fn
        {:conflict, c} -> [c]
        _ -> []
      end)

      # Post-merge: detect and break any cycles
      cycle_nodes = TreeConflict.break_cycles()

      if cycle_nodes != [] do
        Logger.warning("Broke #{length(cycle_nodes)} cycles after merge")
      end

      %{applied: applied, conflicts: conflicts}
    end)
  end

  defp apply_change(change) do
    node_id = change["node_id"]
    operation = change["operation"]

    case {operation, Repo.get(Node, node_id)} do
      {"create", nil} ->
        insert_remote_node(change)
        {:applied, node_id}

      {"create", _existing} ->
        # Node already exists — treat as update conflict
        apply_update_conflict(node_id, change)

      {"update", nil} ->
        # Node doesn't exist locally — create it
        insert_remote_node(change)
        {:applied, node_id}

      {"update", local_node} ->
        apply_update_conflict(local_node, change)

      {"delete", nil} ->
        {:skipped, node_id}

      {"delete", local_node} ->
        apply_delete_conflict(local_node, change)

      {"move", nil} ->
        {:skipped, node_id}

      {"move", local_node} ->
        apply_move_conflict(local_node, change)

      _ ->
        Logger.warning("Unknown sync operation: #{operation}")
        {:skipped, node_id}
    end
  end

  defp apply_update_conflict(local_node, change) do
    # Check if this is edit vs delete
    if local_node.deleted_at != nil do
      {action, conflict_record} = EditWinsOverDelete.resolve(local_node, change)

      case action do
        :restore_and_apply ->
          restore_and_update(local_node, change)
          record_conflict(local_node.id, conflict_record)
          {:conflict, conflict_record}

        :keep_local ->
          record_conflict(local_node.id, conflict_record)
          {:conflict, conflict_record}
      end
    else
      {action, conflict_record} = LastWriterWins.resolve(local_node, change)

      case action do
        :keep_remote ->
          update_from_change(local_node, change)
          record_conflict(local_node.id, conflict_record)
          {:conflict, conflict_record}

        :keep_local ->
          record_conflict(local_node.id, conflict_record)
          {:conflict, conflict_record}
      end
    end
  end

  defp apply_delete_conflict(local_node, change) do
    if local_node.updated_at != nil and
         local_node.updated_at != local_node.inserted_at do
      # Node was edited locally — edit wins over delete
      {_action, conflict_record} = EditWinsOverDelete.resolve(local_node, change)
      record_conflict(local_node.id, conflict_record)
      {:conflict, conflict_record}
    else
      # No local edits — accept the delete
      Repo.query!(
        "UPDATE nodes SET deleted_at = ?1 WHERE id = ?2",
        [DateTime.utc_now() |> DateTime.to_iso8601(), local_node.id]
      )

      {:applied, local_node.id}
    end
  end

  defp apply_move_conflict(local_node, change) do
    {action, conflict_record} = TreeConflict.resolve_move(local_node, change)

    case action do
      :keep_remote ->
        new_parent_id = change["data"]["parent_id"]
        new_position = change["data"]["position"] || 0

        if new_parent_id do
          # Simple move — full path rebuild happens in cycle detection
          Repo.query!(
            "UPDATE nodes SET parent_id = ?1, position = ?2, updated_at = ?3 WHERE id = ?4",
            [
              new_parent_id,
              new_position,
              DateTime.utc_now() |> DateTime.to_iso8601(),
              local_node.id
            ]
          )
        end

        record_conflict(local_node.id, conflict_record)
        {:conflict, conflict_record}

      :keep_local ->
        record_conflict(local_node.id, conflict_record)
        {:conflict, conflict_record}
    end
  end

  defp insert_remote_node(change) do
    data = change["data"] || %{}
    attrs = Format.deserialize_node(data)
    path = Rio.Ecto.PathType.serialize_path(attrs.path || [])
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    Repo.query!(
      """
      INSERT OR IGNORE INTO nodes (
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
        attrs.id || change["node_id"],
        attrs.title || "",
        Jason.encode!(attrs.body || %{}),
        bool_to_int(attrs.is_todo),
        bool_to_int(attrs.todo_completed),
        path,
        attrs.position || 0,
        attrs.depth || 0,
        attrs.edge_label,
        attrs.parent_id,
        attrs.priority,
        attrs.link,
        format_val(attrs.due_date),
        format_val(attrs.completed_at),
        bool_to_int(attrs.locked),
        format_val(attrs.deleted_at),
        attrs.deletion_batch_id,
        format_val(attrs.archived_at),
        attrs.archive_batch_id,
        now,
        now
      ]
    )
  end

  defp update_from_change(local_node, change) do
    data = change["data"] || %{}

    updates =
      data
      |> Enum.filter(fn {k, _v} -> k not in ["id", "inserted_at"] end)
      |> Enum.map(fn
        {"body", v} when is_map(v) -> {"body", Jason.encode!(v)}
        {"path", v} when is_list(v) -> {"path", Rio.Ecto.PathType.serialize_path(v)}
        {"is_todo", v} -> {"is_todo", bool_to_int(v)}
        {"todo_completed", v} -> {"todo_completed", bool_to_int(v)}
        {"locked", v} -> {"locked", bool_to_int(v)}
        other -> other
      end)

    unless Enum.empty?(updates) do
      set_clauses = updates |> Enum.map(fn {k, _} -> "#{k} = ?" end) |> Enum.join(", ")
      values = Enum.map(updates, fn {_, v} -> v end)

      Repo.query!(
        "UPDATE nodes SET #{set_clauses} WHERE id = ?",
        values ++ [local_node.id]
      )
    end
  end

  defp restore_and_update(local_node, change) do
    Repo.query!(
      "UPDATE nodes SET deleted_at = NULL, deletion_batch_id = NULL WHERE id = ?1",
      [local_node.id]
    )

    update_from_change(local_node, change)
  end

  defp record_conflict(node_id, conflict_record) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Repo.query!(
      """
      INSERT INTO sync_conflicts (id, node_id, conflict_type, local_state, remote_state, resolution, resolved_at, inserted_at)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
      """,
      [
        id,
        node_id,
        conflict_record.conflict_type,
        conflict_record.local_state,
        conflict_record.remote_state,
        conflict_record.resolution,
        now,
        now
      ]
    )
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
  defp bool_to_int(nil), do: 0

  defp format_val(nil), do: nil
  defp format_val(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_val(%Date{} = d), do: Date.to_iso8601(d)
  defp format_val(v), do: v
end
