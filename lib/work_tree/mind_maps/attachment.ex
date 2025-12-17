defmodule WorkTree.MindMaps.Attachment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type_values ~w(link image)

  schema "attachments" do
    field :type, :string
    field :url, :string
    field :file_path, :string
    field :title, :string
    field :metadata, :map, default: %{}
    field :position, :integer, default: 0

    belongs_to :node, WorkTree.MindMaps.Node

    timestamps()
  end

  @doc false
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:type, :url, :file_path, :title, :metadata, :position, :node_id])
    |> validate_required([:type, :node_id])
    |> validate_inclusion(:type, @type_values)
    |> validate_has_source()
  end

  defp validate_has_source(changeset) do
    url = get_field(changeset, :url)
    file_path = get_field(changeset, :file_path)

    if is_nil(url) and is_nil(file_path) do
      add_error(changeset, :url, "either url or file_path must be provided")
    else
      changeset
    end
  end
end
