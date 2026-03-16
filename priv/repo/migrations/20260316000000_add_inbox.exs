defmodule Rio.Repo.Migrations.AddInbox do
  use Ecto.Migration

  def change do
    create table(:inbox_items, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false
      add :title, :string, null: false
      add :body, :text, default: "{}"
      add :is_todo, :boolean, default: false, null: false
      add :priority, :integer
      add :link, :string
      add :due_date, :date
      add :edge_label, :string

      # Inbox-specific fields
      add :status, :string, null: false, default: "pending"
      add :source, :string, null: false, default: "manual"
      add :expires_at, :utc_datetime
      add :metadata, :text, default: "{}"

      # Auto-placement hints
      add :target_parent_id, references(:nodes, type: :binary_id, on_delete: :nilify_all)
      add :target_parent_alias, :string

      # Set after placement
      add :node_id, references(:nodes, type: :binary_id, on_delete: :nilify_all)
      add :placed_at, :utc_datetime

      timestamps()
    end

    create index(:inbox_items, [:status])
    create index(:inbox_items, [:expires_at])
    create index(:inbox_items, [:target_parent_id])

    # Add alias to nodes for API targeting
    alter table(:nodes) do
      add :alias, :string
    end

    create unique_index(:nodes, [:alias], where: "alias IS NOT NULL")
  end
end
