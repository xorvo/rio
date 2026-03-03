defmodule WorkTree.Sync.ChangesetReader do
  @moduledoc """
  Reads `.wtxc` changeset files from other devices in the sync directory.
  """

  alias WorkTree.Sync.{Device, VectorClock}

  require Logger

  @doc """
  Scans the sync directory for new changeset files from remote devices.
  Returns a list of `{device_id, changeset_data}` tuples, sorted by sequence.
  """
  def scan_remote_changesets(sync_dir) do
    local_id = Device.local_device_id()
    local_device = Device.get_or_create_local()
    local_clock = VectorClock.decode(local_device.vector_clock)
    changesets_dir = Path.join(sync_dir, "changesets")

    if File.dir?(changesets_dir) do
      changesets_dir
      |> File.ls!()
      |> Enum.reject(&(&1 == local_id))
      |> Enum.flat_map(fn device_id ->
        read_new_changesets(changesets_dir, device_id, local_clock)
      end)
      |> Enum.sort_by(fn {_device_id, changeset} ->
        changeset["sequence_range"]["to"]
      end)
    else
      []
    end
  end

  @doc """
  Reads the manifest file from the sync directory.
  Returns the manifest map or an empty map if not found.
  """
  def read_manifest(sync_dir) do
    path = Path.join(sync_dir, "manifest.json")

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, manifest} -> manifest
          _ -> %{"devices" => []}
        end

      _ ->
        %{"devices" => []}
    end
  end

  @doc """
  Updates the manifest with this device's info.
  """
  def update_manifest(sync_dir) do
    manifest = read_manifest(sync_dir)
    device = Device.get_or_create_local()

    device_entry = %{
      "device_id" => device.device_id,
      "device_name" => device.device_name,
      "last_seen" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "sequence_number" => device.sequence_number
    }

    devices =
      manifest
      |> Map.get("devices", [])
      |> Enum.reject(&(&1["device_id"] == device.device_id))
      |> List.insert_at(0, device_entry)

    updated = Map.put(manifest, "devices", devices)
    path = Path.join(sync_dir, "manifest.json")
    File.mkdir_p!(sync_dir)
    File.write!(path, Jason.encode!(updated, pretty: true))
  end

  # --- Private ---

  defp read_new_changesets(changesets_dir, device_id, local_clock) do
    device_dir = Path.join(changesets_dir, device_id)
    last_known_seq = VectorClock.get(local_clock, device_id)

    if File.dir?(device_dir) do
      device_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".wtxc"))
      |> Enum.map(fn filename ->
        seq = filename |> String.trim_trailing(".wtxc") |> String.to_integer()
        {seq, filename}
      end)
      |> Enum.filter(fn {seq, _} -> seq > last_known_seq end)
      |> Enum.sort_by(fn {seq, _} -> seq end)
      |> Enum.flat_map(fn {_seq, filename} ->
        path = Path.join(device_dir, filename)

        case File.read(path) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, changeset} -> [{device_id, changeset}]
              _ ->
                Logger.warning("Failed to parse changeset: #{path}")
                []
            end

          _ ->
            Logger.warning("Failed to read changeset: #{path}")
            []
        end
      end)
    else
      []
    end
  end
end
