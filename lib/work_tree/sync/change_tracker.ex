defmodule WorkTree.Sync.ChangeTracker do
  @moduledoc """
  Captures local changes and queues them as pending sync operations.

  Call `track/3` after any node mutation to record the change
  for later flush to a changeset file.
  """

  alias WorkTree.Repo
  alias WorkTree.Sync.Device

  @doc """
  Records a pending change for sync.

  Operations: "create", "update", "delete", "move"
  """
  def track(node_id, operation, data \\ %{}) do
    seq = Device.next_sequence!()
    id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Repo.query!(
      """
      INSERT INTO sync_pending_changes (id, node_id, operation, data, sequence_number, inserted_at)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6)
      """,
      [id, node_id, operation, Jason.encode!(data), seq, now]
    )

    # Also update the node's sync metadata
    Repo.query!(
      "UPDATE nodes SET last_modified_by = ?1, last_modified_seq = ?2 WHERE id = ?3",
      [Device.local_device_id(), seq, node_id]
    )

    {:ok, seq}
  end

  @doc """
  Returns all pending changes ordered by sequence number.
  """
  def pending_changes do
    Repo.query!(
      "SELECT id, node_id, operation, data, sequence_number, inserted_at FROM sync_pending_changes ORDER BY sequence_number ASC"
    )
    |> Map.get(:rows)
    |> Enum.map(fn [id, node_id, op, data, seq, ts] ->
      %{
        id: id,
        node_id: node_id,
        operation: op,
        data: Jason.decode!(data || "{}"),
        sequence_number: seq,
        inserted_at: ts
      }
    end)
  end

  @doc """
  Clears pending changes up to and including the given sequence number.
  Called after changes have been flushed to a changeset file.
  """
  def clear_through(sequence_number) do
    Repo.query!(
      "DELETE FROM sync_pending_changes WHERE sequence_number <= ?1",
      [sequence_number]
    )

    :ok
  end
end
