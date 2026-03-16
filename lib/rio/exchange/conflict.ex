defmodule Rio.Exchange.Conflict do
  @moduledoc """
  Conflict detection and resolution for WTXF merge imports.

  Uses Last-Writer-Wins (LWW) by `updated_at` timestamp as the
  primary conflict resolution strategy.
  """

  @type resolution :: :keep_local | :keep_remote | :merged

  @type t :: %{
          node_id: String.t(),
          conflict_type: String.t(),
          local_updated_at: DateTime.t() | nil,
          remote_updated_at: DateTime.t() | nil,
          resolution: resolution(),
          details: String.t() | nil
        }

  @doc """
  Determines which version wins when a node exists in both local DB and import.

  Returns:
    - `:keep_local` if local node is newer or equal
    - `:keep_remote` if remote node is newer
    - `:skip` if nodes are identical
  """
  def resolve_node(local_node, remote_attrs) do
    local_ts = local_node.updated_at
    remote_ts = remote_attrs.updated_at

    cond do
      local_ts == remote_ts ->
        :skip

      remote_ts != nil and (local_ts == nil or DateTime.compare(remote_ts, local_ts) == :gt) ->
        :keep_remote

      true ->
        :keep_local
    end
  end

  @doc """
  Builds a conflict record for logging.
  """
  def build_conflict(node_id, type, local_ts, remote_ts, resolution) do
    %{
      node_id: node_id,
      conflict_type: type,
      local_updated_at: local_ts,
      remote_updated_at: remote_ts,
      resolution: resolution,
      details: nil
    }
  end
end
