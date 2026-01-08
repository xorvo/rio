defmodule WorkTree.Repo.Migrations.AddArchiveToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      # Timestamp when the node was archived (NULL = not archived)
      add :archived_at, :utc_datetime
      # UUID to group nodes archived together (enables batch undo)
      add :archive_batch_id, :uuid
    end

    # Index for efficient filtering of non-archived nodes
    create index(:nodes, [:archived_at])

    # Index for finding all nodes in an archive batch (for undo)
    create index(:nodes, [:archive_batch_id], where: "archive_batch_id IS NOT NULL")

    # Index for auto-archive query: completed todos older than 7 days
    create index(:nodes, [:is_todo, :todo_completed, :completed_at],
      where: "is_todo = true AND todo_completed = true AND archived_at IS NULL"
    )
  end
end
