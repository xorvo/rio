defmodule WorkTree.Sync.Strategies.TreeConflict do
  @moduledoc """
  Tree structural conflict resolution.

  Handles move-vs-move conflicts and cycle detection after merge.
  """

  import Ecto.Query
  alias WorkTree.Repo
  alias WorkTree.MindMaps.Node

  @doc """
  Resolves a move conflict where two devices moved the same node
  to different parents. Uses LWW by timestamp.
  """
  def resolve_move(local_node, remote_change) do
    remote_ts = parse_timestamp(remote_change["data"]["updated_at"])
    local_ts = local_node.updated_at

    if remote_ts != nil and (local_ts == nil or DateTime.compare(remote_ts, local_ts) == :gt) do
      {:keep_remote,
       %{
         conflict_type: "move_vs_move",
         resolution: "keep_remote",
         local_state: Jason.encode!(%{parent_id: local_node.parent_id}),
         remote_state: Jason.encode!(remote_change["data"])
       }}
    else
      {:keep_local,
       %{
         conflict_type: "move_vs_move",
         resolution: "keep_local",
         local_state: Jason.encode!(%{parent_id: local_node.parent_id}),
         remote_state: Jason.encode!(remote_change["data"])
       }}
    end
  end

  @doc """
  Detects cycles in the node tree after a merge operation.
  Returns a list of node IDs that form cycles.
  """
  def detect_cycles do
    nodes =
      Node
      |> where([n], is_nil(n.deleted_at))
      |> select([n], %{id: n.id, parent_id: n.parent_id})
      |> Repo.all()

    parent_map = Map.new(nodes, &{&1.id, &1.parent_id})

    nodes
    |> Enum.filter(fn node ->
      has_cycle?(node.id, parent_map, MapSet.new())
    end)
    |> Enum.map(& &1.id)
  end

  @doc """
  Breaks cycles by detaching nodes from their parents (making them roots).
  Returns the list of detached node IDs.
  """
  def break_cycles do
    cycle_nodes = detect_cycles()

    Enum.each(cycle_nodes, fn node_id ->
      Repo.query!(
        "UPDATE nodes SET parent_id = NULL, depth = 0, path = ?1 WHERE id = ?2",
        ["/#{node_id}/", node_id]
      )
    end)

    cycle_nodes
  end

  defp has_cycle?(node_id, parent_map, visited) do
    if MapSet.member?(visited, node_id) do
      true
    else
      case Map.get(parent_map, node_id) do
        nil -> false
        parent_id -> has_cycle?(parent_id, parent_map, MapSet.put(visited, node_id))
      end
    end
  end

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
