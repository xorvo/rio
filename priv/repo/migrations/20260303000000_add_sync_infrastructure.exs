defmodule WorkTree.Repo.Migrations.AddSyncInfrastructure do
  use Ecto.Migration

  def change do
    # Add sync tracking fields to nodes
    alter table(:nodes) do
      add :last_modified_by, :string
      add :last_modified_seq, :integer
    end

    # Device and sync state tracking
    create table(:sync_metadata, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_id, :string, null: false
      add :device_name, :string
      add :sequence_number, :integer, default: 0, null: false
      add :vector_clock, :text, default: "{}"
      add :last_sync_at, :utc_datetime

      timestamps()
    end

    create unique_index(:sync_metadata, [:device_id])

    # Conflict log
    create table(:sync_conflicts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, :binary_id, null: false
      add :conflict_type, :string, null: false
      add :local_state, :text
      add :remote_state, :text
      add :resolution, :string
      add :resolved_at, :utc_datetime

      timestamps(updated_at: false)
    end

    create index(:sync_conflicts, [:node_id])
    create index(:sync_conflicts, [:resolved_at])

    # Pending local changes queue for sync
    create table(:sync_pending_changes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, :binary_id, null: false
      add :operation, :string, null: false
      add :data, :text
      add :sequence_number, :integer, null: false

      timestamps(updated_at: false)
    end

    create index(:sync_pending_changes, [:sequence_number])
  end
end
