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
    # External link URL attached to the node
    field :link, :string

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :attachments, WorkTree.MindMaps.Attachment

    timestamps()
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:title, :body, :is_todo, :todo_completed, :path, :position, :depth, :edge_label, :parent_id, :priority, :link])
    |> validate_required([:title, :path, :position, :depth])
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_url(:link)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _field, value ->
      case value do
        nil -> []
        "" -> []
        url when is_binary(url) ->
          uri = URI.parse(url)
          if uri.scheme in ["http", "https"] and uri.host not in [nil, ""] do
            []
          else
            [{field, "must be a valid URL starting with http:// or https://"}]
          end
        _ -> [{field, "must be a string"}]
      end
    end)
  end
end
