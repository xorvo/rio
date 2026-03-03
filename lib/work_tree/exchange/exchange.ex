defmodule WorkTree.Exchange do
  @moduledoc """
  Public API for WorkTree data export in WTXF format.

  ## Usage

      # Export to a map
      {:ok, data} = WorkTree.Exchange.export()

      # Export to a file
      :ok = WorkTree.Exchange.export_to_file("backup.wtx")

      # Export compressed
      :ok = WorkTree.Exchange.export_to_file("backup.wtx.gz", compress: true)
  """

  alias WorkTree.Exchange.{Exporter, Serializer}

  @doc """
  Exports all data from the database as a WTXF map.

  Options:
    - `:include_events` - Include node events (default: true)
    - `:include_deleted` - Include soft-deleted nodes (default: true)
  """
  def export(opts \\ []) do
    Exporter.export(opts)
  end

  @doc """
  Exports all data to a `.wtx` JSON file.

  Options:
    - `:compress` - Gzip the output (default: false)
    - `:include_events` - Include node events (default: true)
    - `:include_deleted` - Include soft-deleted nodes (default: true)
  """
  def export_to_file(path, opts \\ []) do
    {file_opts, export_opts} = Keyword.split(opts, [:compress])

    with {:ok, data} <- export(export_opts),
         {:ok, binary} <- Serializer.encode_to_binary(data, file_opts) do
      File.write(path, binary)
    end
  end
end
