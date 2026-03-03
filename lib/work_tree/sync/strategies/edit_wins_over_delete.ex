defmodule WorkTree.Sync.Strategies.EditWinsOverDelete do
  @moduledoc """
  Edit-wins-over-delete conflict resolution.

  When one device edits a node and another deletes it,
  the edit wins and the node is restored. This preserves
  data over deletion.
  """

  @doc """
  Resolves an edit-vs-delete conflict.

  If the remote operation is a delete but the local node was edited more recently,
  the node is kept. If the remote is an edit on a locally-deleted node, the node
  is restored.

  Returns `{action, conflict_record}`.
  """
  def resolve(local_node, remote_change) do
    case remote_change["operation"] do
      "delete" ->
        # Remote wants to delete, but we have edits — keep the node
        {:keep_local,
         %{
           conflict_type: "edit_vs_delete",
           resolution: "edit_wins",
           local_state: Jason.encode!(%{id: local_node.id, deleted_at: local_node.deleted_at}),
           remote_state: Jason.encode!(remote_change)
         }}

      _ ->
        # Remote edited a node we deleted — restore it
        {:restore_and_apply,
         %{
           conflict_type: "delete_vs_edit",
           resolution: "edit_wins",
           local_state: Jason.encode!(%{id: local_node.id, deleted_at: local_node.deleted_at}),
           remote_state: Jason.encode!(remote_change)
         }}
    end
  end
end
