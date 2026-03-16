defmodule Rio.Sync.Worker do
  @moduledoc """
  GenServer that periodically syncs via cloud drive folder.

  Runs every 30 seconds when a `sync_dir` is configured:
  1. Flush local pending changes → write `.wtxc` to sync dir
  2. Scan remote device changeset dirs for new files
  3. Apply remote changes with conflict resolution
  4. Update vector clock
  5. Broadcast `:tree_updated` via PubSub so LiveView refreshes
  """

  use GenServer

  alias Rio.Sync.{
    ChangesetWriter,
    ChangesetReader,
    Merger,
    Device,
    VectorClock
  }

  require Logger

  @sync_interval :timer.seconds(30)

  # --- Client API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an immediate sync cycle.
  """
  def sync_now do
    GenServer.cast(__MODULE__, :sync)
  end

  @doc """
  Returns the current sync status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    sync_dir = Keyword.get(opts, :sync_dir)

    state = %{
      sync_dir: sync_dir,
      last_sync: nil,
      sync_count: 0,
      last_error: nil
    }

    if sync_dir do
      schedule_sync()
      Logger.info("Sync worker started, directory: #{sync_dir}")
    else
      Logger.info("Sync worker started in disabled mode (no sync_dir configured)")
    end

    {:ok, state}
  end

  @impl true
  def handle_cast(:sync, %{sync_dir: nil} = state) do
    {:noreply, state}
  end

  def handle_cast(:sync, state) do
    {:noreply, do_sync(state)}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, Map.take(state, [:sync_dir, :last_sync, :sync_count, :last_error]), state}
  end

  @impl true
  def handle_info(:scheduled_sync, %{sync_dir: nil} = state) do
    {:noreply, state}
  end

  def handle_info(:scheduled_sync, state) do
    state = do_sync(state)
    schedule_sync()
    {:noreply, state}
  end

  # --- Sync Logic ---

  defp do_sync(state) do
    try do
      sync_dir = state.sync_dir

      # 1. Update manifest
      ChangesetReader.update_manifest(sync_dir)

      # 2. Flush local changes
      case ChangesetWriter.flush(sync_dir) do
        {:ok, path} ->
          Logger.debug("Flushed local changes to #{path}")

        :noop ->
          :ok
      end

      # 3. Scan and apply remote changesets
      remote_changesets = ChangesetReader.scan_remote_changesets(sync_dir)

      if remote_changesets != [] do
        all_changes =
          remote_changesets
          |> Enum.flat_map(fn {_device_id, changeset} ->
            changeset["changes"] || []
          end)

        case Merger.apply_changes(all_changes) do
          {:ok, result} ->
            Logger.info(
              "Applied #{result.applied} remote changes, #{length(result.conflicts)} conflicts"
            )

          {:error, reason} ->
            Logger.error("Failed to apply remote changes: #{inspect(reason)}")
        end

        # 4. Update vector clock with remote sequences
        device = Device.get_or_create_local()
        clock = VectorClock.decode(device.vector_clock)

        updated_clock =
          Enum.reduce(remote_changesets, clock, fn {device_id, changeset}, acc ->
            remote_seq = get_in(changeset, ["sequence_range", "to"]) || 0
            VectorClock.merge(acc, %{device_id => remote_seq})
          end)

        Device.update_vector_clock!(updated_clock)

        # 5. Broadcast tree update
        Phoenix.PubSub.broadcast(Rio.PubSub, "tree_updates", :tree_updated)
      end

      Device.touch_last_sync!()

      %{state | last_sync: DateTime.utc_now(), sync_count: state.sync_count + 1, last_error: nil}
    rescue
      e ->
        Logger.error("Sync failed: #{Exception.message(e)}")
        %{state | last_error: Exception.message(e)}
    end
  end

  defp schedule_sync do
    Process.send_after(self(), :scheduled_sync, @sync_interval)
  end
end
