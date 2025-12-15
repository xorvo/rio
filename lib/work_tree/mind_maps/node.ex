defmodule WorkTree.MindMaps.Node do
  use Ecto.Schema
  import Ecto.Changeset

  schema "nodes" do
    field :title, :string
    field :body, :map, default: %{}
    field :is_todo, :boolean, default: false
    field :todo_completed, :boolean, default: false
    field :path, :string
    field :position, :integer, default: 0
    field :depth, :integer, default: 0
    field :edge_label, :string
    # Priority uses numeric scale: p0 = highest priority, p1, p2, etc.
    # NULL means no priority set
    field :priority, :integer

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :attachments, WorkTree.MindMaps.Attachment

    timestamps()
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:title, :body, :is_todo, :todo_completed, :path, :position, :depth, :edge_label, :parent_id, :priority])
    |> validate_required([:title, :path, :position, :depth])
    |> validate_number(:priority, greater_than_or_equal_to: 0)
  end
end
