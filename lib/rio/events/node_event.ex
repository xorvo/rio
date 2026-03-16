defmodule Rio.Events.NodeEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types ~w(created updated deleted todo_toggled priority_changed moved)

  schema "node_events" do
    field :event_type, :string
    field :snapshot, :map
    field :metadata, :map, default: %{}

    belongs_to :node, Rio.MindMaps.Node

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:node_id, :event_type, :snapshot, :metadata])
    |> validate_required([:node_id, :event_type, :snapshot])
    |> validate_inclusion(:event_type, @event_types)
    |> foreign_key_constraint(:node_id)
  end

  def event_types, do: @event_types
end
