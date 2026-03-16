defmodule Rio.Inbox.InboxItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending auto_placed placed expired dismissed)
  @sources ~w(manual api)

  schema "inbox_items" do
    field :title, :string
    field :body, :map, default: %{}
    field :is_todo, :boolean, default: false
    field :priority, :integer
    field :link, :string
    field :due_date, :date
    field :edge_label, :string
    field :status, :string, default: "pending"
    field :source, :string, default: "manual"
    field :expires_at, :utc_datetime
    field :metadata, :map, default: %{}
    field :target_parent_alias, :string
    field :placed_at, :utc_datetime

    belongs_to :target_parent, Rio.MindMaps.Node
    belongs_to :node, Rio.MindMaps.Node

    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :title,
      :body,
      :is_todo,
      :priority,
      :link,
      :due_date,
      :edge_label,
      :status,
      :source,
      :expires_at,
      :metadata,
      :target_parent_id,
      :target_parent_alias,
      :node_id,
      :placed_at
    ])
    |> validate_required([:title, :status, :source])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:source, @sources)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
  end

  def statuses, do: @statuses
  def sources, do: @sources
end
