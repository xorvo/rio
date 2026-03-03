defmodule WorkTree.Exchange.Exporter do
  @moduledoc """
  Queries SQLite tables and serializes all data to a WTXF map.
  Runs inside a transaction for a consistent snapshot.
  """

  import Ecto.Query
  alias WorkTree.Repo
  alias WorkTree.MindMaps.{Node, Attachment}
  alias WorkTree.Events.NodeEvent
  alias WorkTree.Exchange.Format

  @doc """
  Exports all data from the database as a WTXF map.

  Options:
    - `:include_events` - Include node events in export (default: true)
    - `:include_deleted` - Include soft-deleted nodes (default: true)
  """
  def export(opts \\ []) do
    include_events = Keyword.get(opts, :include_events, true)
    include_deleted = Keyword.get(opts, :include_deleted, true)

    Repo.transaction(fn ->
      nodes = query_nodes(include_deleted)
      attachments = query_attachments()
      events = if include_events, do: query_events(), else: []

      serialized_nodes = Enum.map(nodes, &Format.serialize_node/1)
      serialized_attachments = Enum.map(attachments, &Format.serialize_attachment/1)
      serialized_events = Enum.map(events, &Format.serialize_event/1)

      build_envelope(serialized_nodes, serialized_attachments, serialized_events)
    end)
  end

  defp query_nodes(true) do
    Node
    |> order_by([n], [asc: n.depth, asc: n.position, asc: n.id])
    |> Repo.all()
  end

  defp query_nodes(false) do
    Node
    |> where([n], is_nil(n.deleted_at))
    |> order_by([n], [asc: n.depth, asc: n.position, asc: n.id])
    |> Repo.all()
  end

  defp query_attachments do
    Attachment
    |> order_by([a], [asc: a.node_id, asc: a.position])
    |> Repo.all()
  end

  defp query_events do
    NodeEvent
    |> order_by([e], [asc: e.inserted_at, asc: e.id])
    |> Repo.all()
  end

  defp build_envelope(nodes, attachments, events) do
    content = Jason.encode!(%{
      "nodes" => nodes,
      "attachments" => attachments,
      "events" => events
    })

    checksum = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    %{
      "wtx_version" => Format.wtx_version(),
      "schema_version" => Format.schema_version(),
      "export_type" => "full",
      "metadata" => %{
        "app_version" => app_version(),
        "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "device_id" => device_id(),
        "device_name" => device_name(),
        "source_db" => "sqlite",
        "node_count" => length(nodes),
        "checksum" => "sha256:#{checksum}"
      },
      "nodes" => nodes,
      "attachments" => attachments,
      "events" => events
    }
  end

  defp app_version do
    case :application.get_key(:work_tree, :vsn) do
      {:ok, vsn} -> to_string(vsn)
      _ -> "0.1.0"
    end
  end

  defp device_id do
    {:ok, hostname} = :inet.gethostname()
    hostname_str = to_string(hostname)
    :crypto.hash(:sha256, hostname_str) |> binary_part(0, 16) |> Base.encode16(case: :lower)
  end

  defp device_name do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end
end
