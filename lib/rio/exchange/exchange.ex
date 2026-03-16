defmodule Rio.Exchange do
  @moduledoc """
  Public API for Rio data export and import using the WTXF format.

  ## Export

      {:ok, data} = Rio.Exchange.export()
      :ok = Rio.Exchange.export_to_file("backup.wtx")

  ## Import

      {:ok, stats} = Rio.Exchange.import_file("backup.wtx")
      {:ok, stats} = Rio.Exchange.import_file("backup.wtx", mode: :merge)
  """

  alias Rio.Exchange.{Exporter, Importer, Format, Serializer}

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

  @doc """
  Imports data from a `.wtx` file into the database.

  Options:
    - `:mode` - `:full` (default) wipes and restores, `:merge` merges with LWW

  Returns `{:ok, stats}` with import statistics or `{:error, reason}`.
  """
  def import_file(path, opts \\ []) do
    with {:ok, data} <- Serializer.decode_file(path),
         :ok <- Format.validate(data) do
      Importer.import_data(data, opts)
    end
  end

  @doc """
  Imports data from a pre-parsed WTXF map.

  Options:
    - `:mode` - `:full` (default) or `:merge`
  """
  def import_data(data, opts \\ []) do
    with :ok <- Format.validate(data) do
      Importer.import_data(data, opts)
    end
  end
end
