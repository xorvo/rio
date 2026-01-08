defmodule WorkTree.Events do
  @moduledoc """
  Context for event sourcing and history tracking.
  Records full node snapshots for each significant change.
  """

  import Ecto.Query
  alias WorkTree.Repo
  alias WorkTree.Events.NodeEvent
  alias WorkTree.MindMaps.Node

  @doc """
  Records an event for a node with a full snapshot.
  """
  def record_event(%Node{} = node, event_type, metadata \\ %{}) do
    snapshot = node_to_snapshot(node)

    %NodeEvent{}
    |> NodeEvent.changeset(%{
      node_id: node.id,
      event_type: event_type,
      snapshot: snapshot,
      metadata: metadata
    })
    |> Repo.insert()
  end

  @doc """
  Gets the history of events for a specific node.
  """
  def get_node_history(node_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    NodeEvent
    |> where([e], e.node_id == ^node_id)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets recent events across all nodes.
  """
  def get_recent_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    event_types = Keyword.get(opts, :event_types)

    query =
      NodeEvent
      |> order_by([e], desc: e.inserted_at)
      |> limit(^limit)

    query =
      if event_types do
        where(query, [e], e.event_type in ^event_types)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Restores a node to a previous snapshot state.
  Returns the updated node.
  """
  def restore_to_snapshot(%NodeEvent{} = event) do
    node = Repo.get!(Node, event.node_id)
    snapshot = event.snapshot

    node
    |> Ecto.Changeset.change(
      Map.take(snapshot, [:title, :body, :is_todo, :todo_completed, :priority, :edge_label])
    )
    |> Repo.update()
  end

  # Convert a node struct to a snapshot map
  defp node_to_snapshot(%Node{} = node) do
    %{
      id: node.id,
      title: node.title,
      body: node.body,
      is_todo: node.is_todo,
      todo_completed: node.todo_completed,
      priority: node.priority,
      path: node.path,
      position: node.position,
      depth: node.depth,
      edge_label: node.edge_label,
      parent_id: node.parent_id
    }
  end
end
