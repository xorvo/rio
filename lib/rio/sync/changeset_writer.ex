defmodule Rio.Sync.ChangesetWriter do
  @moduledoc """
  Writes `.wtxc` changeset files to the sync directory.

  Each file contains a batch of operations from this device,
  identified by device ID and sequence range.
  """

  alias Rio.Sync.{ChangeTracker, Device, VectorClock}

  @doc """
  Flushes pending local changes to a `.wtxc` file in the sync directory.
  Returns `{:ok, path}` if changes were written, `:noop` if no pending changes.
  """
  def flush(sync_dir) do
    changes = ChangeTracker.pending_changes()

    if Enum.empty?(changes) do
      :noop
    else
      device = Device.get_or_create_local()
      max_seq = changes |> Enum.map(& &1.sequence_number) |> Enum.max()

      changeset = %{
        "wtxc_version" => "1.0.0",
        "device_id" => device.device_id,
        "device_name" => device.device_name,
        "sequence_range" => %{
          "from" => List.first(changes).sequence_number,
          "to" => max_seq
        },
        "vector_clock" => VectorClock.decode(device.vector_clock),
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "changes" => Enum.map(changes, &serialize_change/1)
      }

      dir = Path.join([sync_dir, "changesets", device.device_id])
      File.mkdir_p!(dir)
      path = Path.join(dir, "#{max_seq}.wtxc")
      File.write!(path, Jason.encode!(changeset, pretty: true))

      ChangeTracker.clear_through(max_seq)

      {:ok, path}
    end
  end

  @doc """
  Writes a full snapshot `.wtx` file for new device bootstrapping.
  """
  def write_snapshot(sync_dir) do
    device = Device.get_or_create_local()
    dir = Path.join(sync_dir, "snapshots")
    File.mkdir_p!(dir)
    path = Path.join(dir, "latest-#{device.device_id}.wtx")

    Rio.Exchange.export_to_file(path)
  end

  defp serialize_change(change) do
    %{
      "node_id" => change.node_id,
      "operation" => change.operation,
      "data" => change.data,
      "sequence_number" => change.sequence_number,
      "timestamp" => change.inserted_at
    }
  end
end
