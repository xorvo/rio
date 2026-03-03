defmodule WorkTree.Exchange.Format do
  @moduledoc """
  WTXF (WorkTree Exchange Format) constants and entity serialization.

  Handles converting Ecto structs with Postgres-specific types
  (binary UUIDs, ltree paths, NaiveDateTime) into portable maps.
  """

  @wtx_version "1.0.0"
  @schema_version 1

  def wtx_version, do: @wtx_version
  def schema_version, do: @schema_version

  @doc """
  Serializes a Node struct into a portable map.
  """
  def serialize_node(node) do
    %{
      "id" => encode_uuid(node.id),
      "title" => node.title,
      "body" => node.body || %{},
      "is_todo" => node.is_todo,
      "todo_completed" => node.todo_completed,
      "path" => serialize_path(node.path),
      "position" => node.position,
      "depth" => node.depth,
      "edge_label" => node.edge_label,
      "parent_id" => encode_uuid(node.parent_id),
      "priority" => node.priority,
      "link" => node.link,
      "due_date" => serialize_date(node.due_date),
      "completed_at" => serialize_datetime(node.completed_at),
      "locked" => node.locked,
      "deleted_at" => serialize_datetime(node.deleted_at),
      "deletion_batch_id" => encode_uuid(node.deletion_batch_id),
      "archived_at" => serialize_datetime(node.archived_at),
      "archive_batch_id" => encode_uuid(node.archive_batch_id),
      "inserted_at" => serialize_datetime(node.inserted_at),
      "updated_at" => serialize_datetime(node.updated_at)
    }
  end

  @doc """
  Serializes an Attachment struct into a portable map.
  """
  def serialize_attachment(attachment) do
    %{
      "id" => encode_uuid(attachment.id),
      "node_id" => encode_uuid(attachment.node_id),
      "type" => attachment.type,
      "url" => attachment.url,
      "file_path" => attachment.file_path,
      "title" => attachment.title,
      "metadata" => attachment.metadata || %{},
      "position" => attachment.position,
      "inserted_at" => serialize_datetime(attachment.inserted_at),
      "updated_at" => serialize_datetime(attachment.updated_at)
    }
  end

  @doc """
  Serializes a NodeEvent struct into a portable map.
  """
  def serialize_event(event) do
    %{
      "id" => encode_uuid(event.id),
      "node_id" => encode_uuid(event.node_id),
      "event_type" => event.event_type,
      "snapshot" => serialize_snapshot(event.snapshot),
      "metadata" => event.metadata || %{},
      "inserted_at" => serialize_datetime(event.inserted_at)
    }
  end

  @doc """
  Converts a path (Postgres array of binary UUIDs) to a list of hex UUID strings.
  """
  def serialize_path(nil), do: []
  def serialize_path(path) when is_list(path), do: Enum.map(path, &encode_uuid/1)

  @doc """
  Encodes a UUID to a hex string. Handles both binary and already-string UUIDs.
  """
  def encode_uuid(nil), do: nil

  def encode_uuid(<<_::128>> = binary_uuid) do
    Ecto.UUID.cast!(binary_uuid)
  end

  def encode_uuid(uuid) when is_binary(uuid) do
    # Already a hex string — validate and return
    case Ecto.UUID.cast(uuid) do
      {:ok, hex} -> hex
      :error -> uuid
    end
  end

  defp serialize_datetime(nil), do: nil

  defp serialize_datetime(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end

  defp serialize_datetime(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp serialize_date(nil), do: nil
  defp serialize_date(%Date{} = d), do: Date.to_iso8601(d)

  defp serialize_snapshot(nil), do: %{}

  defp serialize_snapshot(snapshot) when is_map(snapshot) do
    snapshot
    |> maybe_encode_field("id")
    |> maybe_encode_field("parent_id")
    |> maybe_encode_field("deletion_batch_id")
    |> maybe_encode_field("archive_batch_id")
    |> maybe_serialize_path_field()
    |> maybe_serialize_datetime_field("inserted_at")
    |> maybe_serialize_datetime_field("updated_at")
    |> maybe_serialize_datetime_field("deleted_at")
    |> maybe_serialize_datetime_field("completed_at")
    |> maybe_serialize_datetime_field("archived_at")
    |> maybe_serialize_date_field("due_date")
  end

  defp maybe_encode_field(map, key) do
    case Map.get(map, key) do
      nil -> map
      val -> Map.put(map, key, encode_uuid(val))
    end
  end

  defp maybe_serialize_path_field(map) do
    case Map.get(map, "path") do
      nil -> map
      path -> Map.put(map, "path", serialize_path(path))
    end
  end

  defp maybe_serialize_datetime_field(map, key) do
    case Map.get(map, key) do
      nil -> map
      %DateTime{} = dt -> Map.put(map, key, DateTime.to_iso8601(dt))
      %NaiveDateTime{} = ndt -> Map.put(map, key, ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601())
      val when is_binary(val) -> map
      _ -> map
    end
  end

  defp maybe_serialize_date_field(map, key) do
    case Map.get(map, key) do
      nil -> map
      %Date{} = d -> Map.put(map, key, Date.to_iso8601(d))
      val when is_binary(val) -> map
      _ -> map
    end
  end
end
