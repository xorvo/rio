defmodule Mix.Tasks.WorkTree.Export do
  @moduledoc """
  Exports all WorkTree data to a .wtx exchange file.

  ## Usage

      mix work_tree.export
      mix work_tree.export --output backup.wtx
      mix work_tree.export --output backup.wtx.gz --compress
      mix work_tree.export --no-events
  """

  use Mix.Task

  @shortdoc "Export WorkTree data to a .wtx file"

  @switches [
    output: :string,
    compress: :boolean,
    events: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    Mix.Task.run("app.start")

    output = Keyword.get(opts, :output, default_output(opts))
    compress = Keyword.get(opts, :compress, false)
    include_events = Keyword.get(opts, :events, true)

    Mix.shell().info("Exporting WorkTree data...")

    case WorkTree.Exchange.export_to_file(output,
           compress: compress,
           include_events: include_events
         ) do
      :ok ->
        file_size = File.stat!(output).size |> format_size()
        Mix.shell().info("Export complete: #{output} (#{file_size})")

      {:error, reason} ->
        Mix.shell().error("Export failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp default_output(opts) do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d_%H%M%S")
    ext = if Keyword.get(opts, :compress, false), do: ".wtx.gz", else: ".wtx"
    "work_tree_export_#{timestamp}#{ext}"
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
