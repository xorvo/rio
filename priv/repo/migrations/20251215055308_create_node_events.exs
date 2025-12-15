defmodule WorkTree.Repo.Migrations.CreateNodeEvents do
  use Ecto.Migration

  def change do
    create table(:node_events) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      # Store full node snapshot as JSON for event sourcing
      add :snapshot, :map, null: false
      # Optional metadata (e.g., user context, trigger info)
      add :metadata, :map, default: %{}

      timestamps(updated_at: false)
    end

    create index(:node_events, [:node_id])
    create index(:node_events, [:event_type])
    create index(:node_events, [:inserted_at])
  end
end
