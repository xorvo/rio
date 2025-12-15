defmodule WorkTree.Repo.Migrations.CreateNodes do
  use Ecto.Migration

  def change do
    create table(:nodes) do
      add :parent_id, references(:nodes, on_delete: :delete_all)
      add :title, :string, null: false
      add :body, :map, default: %{}
      add :is_todo, :boolean, default: false, null: false
      add :todo_completed, :boolean, default: false, null: false
      add :path, :string, null: false
      add :position, :integer, null: false, default: 0
      add :depth, :integer, null: false, default: 0
      add :edge_label, :string

      timestamps()
    end

    create index(:nodes, [:parent_id])
    create index(:nodes, [:path])
  end
end
