defmodule WorkTree.Repo.Migrations.AddSoftDeleteToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      # Timestamp when the node was soft-deleted (NULL = not deleted)
      add :deleted_at, :utc_datetime
      # UUID to group nodes deleted together (enables batch undo)
      add :deletion_batch_id, :uuid
    end

    # Index for efficient filtering of non-deleted nodes
    create index(:nodes, [:deleted_at])
    # Index for finding all nodes in a deletion batch
    create index(:nodes, [:deletion_batch_id], where: "deletion_batch_id IS NOT NULL")
  end
end
