defmodule MindMapperPoc.Repo.Migrations.CreateAttachments do
  use Ecto.Migration

  def change do
    create table(:attachments) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :url, :string
      add :file_path, :string
      add :title, :string
      add :metadata, :map, default: %{}
      add :position, :integer, null: false, default: 0

      timestamps()
    end

    create index(:attachments, [:node_id])
  end
end
