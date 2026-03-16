defmodule Rio.Sync do
  @moduledoc """
  Public API for Rio sync infrastructure.

  Sync works via a shared cloud drive folder (iCloud, Dropbox, etc.)
  where devices exchange changeset files (.wtxc) and snapshots (.wtx).

  ## Configuration

  Set the `RIO_SYNC_DIR` environment variable to enable sync:

      export RIO_SYNC_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Rio/sync"

  ## Usage

      # Check sync status
      Rio.Sync.status()

      # Trigger immediate sync
      Rio.Sync.sync_now()

      # Track a local change for sync
      Rio.Sync.track_change(node_id, "update", %{title: "New title"})

      # Get this device's identity
      Rio.Sync.device_info()
  """

  alias Rio.Sync.{Worker, ChangeTracker, Device}

  @doc """
  Returns the current sync status.
  """
  def status do
    Worker.status()
  end

  @doc """
  Triggers an immediate sync cycle.
  """
  def sync_now do
    Worker.sync_now()
  end

  @doc """
  Records a local change for eventual sync.

  Operations: "create", "update", "delete", "move"
  """
  def track_change(node_id, operation, data \\ %{}) do
    ChangeTracker.track(node_id, operation, data)
  end

  @doc """
  Returns the local device identity info.
  """
  def device_info do
    Device.get_or_create_local()
  end

  @doc """
  Returns the configured sync directory, or nil if sync is disabled.
  """
  def sync_dir do
    Application.get_env(:rio, :sync_dir)
  end

  @doc """
  Returns true if sync is enabled (sync_dir is configured).
  """
  def enabled? do
    sync_dir() != nil
  end
end
