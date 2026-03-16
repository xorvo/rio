defmodule Rio.Sync.Strategies.LastWriterWins do
  @moduledoc """
  Last-Writer-Wins conflict resolution strategy.

  Compares timestamps to determine which version takes precedence.
  The losing edit is preserved as a sync conflict record for review.
  """

  @doc """
  Resolves an edit-vs-edit conflict by timestamp.
  Returns `{:keep_remote, conflict_record}` or `{:keep_local, conflict_record}`.
  """
  def resolve(local_node, remote_change) do
    local_ts = local_node.updated_at
    remote_ts = parse_timestamp(remote_change["data"]["updated_at"])

    if remote_ts != nil and (local_ts == nil or DateTime.compare(remote_ts, local_ts) == :gt) do
      {:keep_remote,
       %{
         conflict_type: "edit_vs_edit",
         resolution: "keep_remote",
         local_state: Jason.encode!(snapshot_node(local_node)),
         remote_state: Jason.encode!(remote_change["data"])
       }}
    else
      {:keep_local,
       %{
         conflict_type: "edit_vs_edit",
         resolution: "keep_local",
         local_state: Jason.encode!(snapshot_node(local_node)),
         remote_state: Jason.encode!(remote_change["data"])
       }}
    end
  end

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp snapshot_node(node) do
    %{
      id: node.id,
      title: node.title,
      body: node.body,
      updated_at: node.updated_at && DateTime.to_iso8601(node.updated_at)
    }
  end
end
