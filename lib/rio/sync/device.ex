defmodule Rio.Sync.Device do
  @moduledoc """
  Device identity management for sync.

  Each device has a stable UUID and human-readable name.
  The device ID persists across app restarts via the sync_metadata table.
  """

  import Ecto.Query
  alias Rio.Repo
  alias Rio.Sync.VectorClock

  @doc """
  Gets or creates the local device identity.
  Returns `{device_id, device_name, sequence_number}`.
  """
  def get_or_create_local do
    case get_local() do
      nil -> create_local()
      device -> device
    end
  end

  @doc """
  Gets the local device record, or nil if not initialized.
  """
  def get_local do
    query =
      from(s in "sync_metadata",
        where: s.device_id == ^local_device_id(),
        select: %{
          id: s.id,
          device_id: s.device_id,
          device_name: s.device_name,
          sequence_number: s.sequence_number,
          vector_clock: s.vector_clock,
          last_sync_at: s.last_sync_at
        },
        limit: 1
      )

    Repo.one(query)
  end

  @doc """
  Increments the local device's sequence number and returns the new value.
  """
  def next_sequence! do
    device = get_or_create_local()
    new_seq = device.sequence_number + 1

    Repo.query!(
      "UPDATE sync_metadata SET sequence_number = ?1, updated_at = ?2 WHERE device_id = ?3",
      [new_seq, DateTime.utc_now() |> DateTime.to_iso8601(), device.device_id]
    )

    new_seq
  end

  @doc """
  Updates the vector clock for the local device.
  """
  def update_vector_clock!(clock) do
    Repo.query!(
      "UPDATE sync_metadata SET vector_clock = ?1, updated_at = ?2 WHERE device_id = ?3",
      [VectorClock.encode(clock), DateTime.utc_now() |> DateTime.to_iso8601(), local_device_id()]
    )
  end

  @doc """
  Updates the last sync timestamp.
  """
  def touch_last_sync! do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Repo.query!(
      "UPDATE sync_metadata SET last_sync_at = ?1, updated_at = ?2 WHERE device_id = ?3",
      [now, now, local_device_id()]
    )
  end

  @doc """
  Returns a stable device ID derived from the machine's hostname.
  """
  def local_device_id do
    {:ok, hostname} = :inet.gethostname()
    hostname_str = to_string(hostname)

    uuid_bytes = :crypto.hash(:sha256, hostname_str) |> binary_part(0, 16)

    <<a::32, b::16, c::16, d::16, e::48>> = uuid_bytes

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a, b, c, d, e]
    )
    |> to_string()
  end

  @doc """
  Returns the device's human-readable name.
  """
  def local_device_name do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end

  # --- Private ---

  defp create_local do
    id = Ecto.UUID.generate()
    device_id = local_device_id()
    device_name = local_device_name()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Repo.query!(
      """
      INSERT INTO sync_metadata (id, device_id, device_name, sequence_number, vector_clock, inserted_at, updated_at)
      VALUES (?1, ?2, ?3, 0, '{}', ?4, ?4)
      """,
      [id, device_id, device_name, now]
    )

    get_local()
  end
end
