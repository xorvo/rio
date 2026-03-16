defmodule Rio.MindMaps.Node do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "nodes" do
    field :title, :string
    field :body, :map, default: %{}
    field :is_todo, :boolean, default: false
    field :todo_completed, :boolean, default: false
    field :path, Rio.Ecto.PathType, default: []
    field :position, :integer, default: 0
    field :depth, :integer, default: 0
    field :edge_label, :string
    # Priority uses numeric scale: p0 = highest priority, p1, p2, etc.
    # NULL means no priority set
    field :priority, :integer
    # External link URL attached to the node
    field :link, :string
    # Due date for the node
    field :due_date, :date
    # Timestamp when todo was marked as completed
    field :completed_at, :utc_datetime
    # Locked nodes cannot be deleted
    field :locked, :boolean, default: false
    # Soft delete fields
    field :deleted_at, :utc_datetime
    field :deletion_batch_id, Ecto.UUID
    # Archive fields
    field :archived_at, :utc_datetime
    field :archive_batch_id, Ecto.UUID
    # Short memorable name for API targeting
    field :alias, :string

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :attachments, Rio.MindMaps.Attachment

    timestamps()
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :title,
      :body,
      :is_todo,
      :todo_completed,
      :path,
      :position,
      :depth,
      :edge_label,
      :parent_id,
      :priority,
      :link,
      :due_date,
      :completed_at,
      :locked,
      :archived_at,
      :archive_batch_id,
      :alias
    ])
    |> validate_required([:title, :path, :position, :depth])
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_url(:link)
    |> validate_alias()
  end

  @doc """
  Changeset for inline node creation where title starts empty.
  Used when creating nodes that will be edited immediately.
  """
  def inline_changeset(node, attrs) do
    node
    |> cast(attrs, [
      :title,
      :body,
      :is_todo,
      :todo_completed,
      :path,
      :position,
      :depth,
      :edge_label,
      :parent_id,
      :priority,
      :link,
      :due_date,
      :completed_at,
      :locked,
      :archived_at,
      :archive_batch_id,
      :alias
    ])
    |> validate_required([:path, :position, :depth])
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_url(:link)
    |> validate_alias()
    |> put_default_title()
  end

  defp put_default_title(changeset) do
    case get_field(changeset, :title) do
      nil -> put_change(changeset, :title, "")
      "" -> changeset
      _ -> changeset
    end
  end

  defp validate_alias(changeset) do
    changeset
    |> validate_format(:alias, ~r/^[a-z0-9_-]+$/,
      message: "must contain only lowercase letters, numbers, hyphens, and underscores"
    )
    |> unique_constraint(:alias)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _field, value ->
      case value do
        nil ->
          []

        "" ->
          []

        url when is_binary(url) ->
          uri = URI.parse(url)

          if uri.scheme in ["http", "https"] and uri.host not in [nil, ""] do
            []
          else
            [{field, "must be a valid URL starting with http:// or https://"}]
          end

        _ ->
          [{field, "must be a string"}]
      end
    end)
  end
end
