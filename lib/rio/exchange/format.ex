defmodule Rio.Exchange.Format do
  @moduledoc """
  WTXF (Rio Exchange Format) constants, validation, and entity serialization.

  Handles converting Ecto structs with SQLite-specific types
  (PathType delimited strings, binary IDs) into portable maps,
  and parsing portable maps back into DB-ready attributes.
  """

  @wtx_version "1.0.0"
  @schema_version 1

  def wtx_version, do: @wtx_version
  def schema_version, do: @schema_version

  # --- Serialization (DB → WTXF) ---

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
      "snapshot" => event.snapshot || %{},
      "metadata" => event.metadata || %{},
      "inserted_at" => serialize_datetime(event.inserted_at)
    }
  end

  # --- Deserialization (WTXF → DB attrs) ---

  @doc """
  Converts a WTXF node map into attributes suitable for DB insertion.
  """
  def deserialize_node(map) do
    %{
      id: map["id"],
      title: map["title"],
      body: map["body"] || %{},
      is_todo: map["is_todo"] || false,
      todo_completed: map["todo_completed"] || false,
      path: map["path"] || [],
      position: map["position"] || 0,
      depth: map["depth"] || 0,
      edge_label: map["edge_label"],
      parent_id: map["parent_id"],
      priority: map["priority"],
      link: map["link"],
      due_date: parse_date(map["due_date"]),
      completed_at: parse_datetime(map["completed_at"]),
      locked: map["locked"] || false,
      deleted_at: parse_datetime(map["deleted_at"]),
      deletion_batch_id: map["deletion_batch_id"],
      archived_at: parse_datetime(map["archived_at"]),
      archive_batch_id: map["archive_batch_id"],
      inserted_at: parse_datetime(map["inserted_at"]),
      updated_at: parse_datetime(map["updated_at"])
    }
  end

  @doc """
  Converts a WTXF attachment map into attributes suitable for DB insertion.
  """
  def deserialize_attachment(map) do
    %{
      id: map["id"],
      node_id: map["node_id"],
      type: map["type"],
      url: map["url"],
      file_path: map["file_path"],
      title: map["title"],
      metadata: map["metadata"] || %{},
      position: map["position"] || 0,
      inserted_at: parse_datetime(map["inserted_at"]),
      updated_at: parse_datetime(map["updated_at"])
    }
  end

  @doc """
  Converts a WTXF event map into attributes suitable for DB insertion.
  """
  def deserialize_event(map) do
    %{
      id: map["id"],
      node_id: map["node_id"],
      event_type: map["event_type"],
      snapshot: map["snapshot"] || %{},
      metadata: map["metadata"] || %{},
      inserted_at: parse_datetime(map["inserted_at"])
    }
  end

  # --- Validation ---

  @doc """
  Validates a parsed WTXF envelope. Returns `:ok` or `{:error, reason}`.
  """
  def validate(data) when is_map(data) do
    with :ok <- validate_version(data),
         :ok <- validate_structure(data),
         :ok <- validate_checksum(data) do
      :ok
    end
  end

  def validate(_), do: {:error, "invalid WTXF data: expected a map"}

  defp validate_version(data) do
    case data["wtx_version"] do
      @wtx_version -> :ok
      nil -> {:error, "missing wtx_version"}
      v -> {:error, "unsupported wtx_version: #{v} (expected #{@wtx_version})"}
    end
  end

  defp validate_structure(data) do
    cond do
      not is_list(data["nodes"]) -> {:error, "missing or invalid 'nodes' field"}
      not is_list(data["attachments"]) -> {:error, "missing or invalid 'attachments' field"}
      true -> :ok
    end
  end

  defp validate_checksum(data) do
    case get_in(data, ["metadata", "checksum"]) do
      nil ->
        :ok

      "sha256:" <> expected_hash ->
        content = Jason.encode!(%{
          "nodes" => data["nodes"],
          "attachments" => data["attachments"],
          "events" => data["events"] || []
        })

        actual_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

        if actual_hash == expected_hash do
          :ok
        else
          {:error, "checksum mismatch: expected #{expected_hash}, got #{actual_hash}"}
        end

      other ->
        {:error, "unsupported checksum format: #{other}"}
    end
  end

  # --- Helpers ---

  @doc """
  Converts a path (list of UUID strings from PathType) to a plain list of hex UUID strings.
  """
  def serialize_path(nil), do: []
  def serialize_path(path) when is_list(path), do: Enum.map(path, &encode_uuid/1)

  @doc """
  Encodes a UUID to a hex string. Handles binary, hex, and nil.
  """
  def encode_uuid(nil), do: nil

  def encode_uuid(<<_::128>> = binary_uuid) do
    Ecto.UUID.cast!(binary_uuid)
  end

  def encode_uuid(uuid) when is_binary(uuid) do
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

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
