defmodule Mix.Tasks.WorkTree.Import do
  @moduledoc """
  Imports WorkTree data from a .wtx exchange file.

  ## Usage

      mix work_tree.import backup.wtx
      mix work_tree.import backup.wtx --mode full
      mix work_tree.import backup.wtx --mode merge
  """

  use Mix.Task

  @shortdoc "Import WorkTree data from a .wtx file"

  @switches [mode: :string]

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, switches: @switches)

    path =
      case positional do
        [p | _] -> p
        [] ->
          Mix.shell().error("Usage: mix work_tree.import <path.wtx> [--mode full|merge]")
          exit({:shutdown, 1})
      end

    unless File.exists?(path) do
      Mix.shell().error("File not found: #{path}")
      exit({:shutdown, 1})
    end

    mode =
      case Keyword.get(opts, :mode, "full") do
        "full" -> :full
        "merge" -> :merge
        other ->
          Mix.shell().error("Invalid mode: #{other} (expected 'full' or 'merge')")
          exit({:shutdown, 1})
      end

    Mix.Task.run("app.start")

    file_size = File.stat!(path).size |> format_size()
    Mix.shell().info("Importing from #{path} (#{file_size}) in #{mode} mode...")

    if mode == :full do
      unless Mix.shell().yes?("Full import will DELETE all existing data. Continue?") do
        Mix.shell().info("Import cancelled.")
        exit({:shutdown, 0})
      end
    end

    case WorkTree.Exchange.import_file(path, mode: mode) do
      {:ok, stats} ->
        Mix.shell().info("Import complete!")
        Mix.shell().info("  Nodes: #{stats.nodes_imported}")
        Mix.shell().info("  Attachments: #{stats.attachments_imported}")
        Mix.shell().info("  Events: #{stats.events_imported}")

        if length(stats.conflicts) > 0 do
          Mix.shell().info("  Conflicts: #{length(stats.conflicts)}")

          Enum.each(stats.conflicts, fn c ->
            Mix.shell().info("    - #{c.node_id}: #{c.conflict_type} → #{c.resolution}")
          end)
        end

      {:error, reason} ->
        Mix.shell().error("Import failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
