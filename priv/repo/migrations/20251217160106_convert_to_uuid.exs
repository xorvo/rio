defmodule WorkTree.Repo.Migrations.ConvertToUuid do
  use Ecto.Migration

  def up do
    # Enable UUID extension
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""

    # Step 1: Add UUID columns to all tables
    alter table(:nodes) do
      add :uuid, :uuid, default: fragment("uuid_generate_v4()")
      add :parent_uuid, :uuid
    end

    alter table(:attachments) do
      add :uuid, :uuid, default: fragment("uuid_generate_v4()")
      add :node_uuid, :uuid
    end

    alter table(:node_events) do
      add :uuid, :uuid, default: fragment("uuid_generate_v4()")
      add :node_uuid, :uuid
    end

    # Step 2: Populate UUIDs for existing records
    execute "UPDATE nodes SET uuid = uuid_generate_v4() WHERE uuid IS NULL"
    execute "UPDATE attachments SET uuid = uuid_generate_v4() WHERE uuid IS NULL"
    execute "UPDATE node_events SET uuid = uuid_generate_v4() WHERE uuid IS NULL"

    # Step 2b: Add new path column as UUID array
    alter table(:nodes) do
      add :path_new, {:array, :uuid}, default: []
    end

    # Step 3: Create mapping and update foreign keys
    execute """
    UPDATE nodes n
    SET parent_uuid = p.uuid
    FROM nodes p
    WHERE n.parent_id = p.id
    """

    execute """
    UPDATE attachments a
    SET node_uuid = n.uuid
    FROM nodes n
    WHERE a.node_id = n.id
    """

    execute """
    UPDATE node_events ne
    SET node_uuid = n.uuid
    FROM nodes n
    WHERE ne.node_id = n.id
    """

    # Step 4: Drop old constraints and indexes
    drop constraint(:nodes, "nodes_parent_id_fkey")
    drop constraint(:attachments, "attachments_node_id_fkey")
    drop constraint(:node_events, "node_events_node_id_fkey")

    drop index(:nodes, [:parent_id])
    drop index(:attachments, [:node_id])
    drop index(:node_events, [:node_id])

    # Step 5: Drop old columns
    alter table(:nodes) do
      remove :id
      remove :parent_id
    end

    alter table(:attachments) do
      remove :id
      remove :node_id
    end

    alter table(:node_events) do
      remove :id
      remove :node_id
    end

    # Step 6: Rename UUID columns
    rename table(:nodes), :uuid, to: :id
    rename table(:nodes), :parent_uuid, to: :parent_id
    rename table(:attachments), :uuid, to: :id
    rename table(:attachments), :node_uuid, to: :node_id
    rename table(:node_events), :uuid, to: :id
    rename table(:node_events), :node_uuid, to: :node_id

    # Step 7: Add primary key constraints
    execute "ALTER TABLE nodes ADD PRIMARY KEY (id)"
    execute "ALTER TABLE attachments ADD PRIMARY KEY (id)"
    execute "ALTER TABLE node_events ADD PRIMARY KEY (id)"

    # Step 8: Add foreign key constraints
    alter table(:nodes) do
      modify :parent_id, references(:nodes, type: :uuid, on_delete: :delete_all)
    end

    alter table(:attachments) do
      modify :node_id, references(:nodes, type: :uuid, on_delete: :delete_all), null: false
    end

    alter table(:node_events) do
      modify :node_id, references(:nodes, type: :uuid, on_delete: :delete_all), null: false
    end

    # Step 9: Recreate indexes
    create index(:nodes, [:parent_id])
    create index(:attachments, [:node_id])
    create index(:node_events, [:node_id])

    # Step 10: Rebuild path field as UUID array
    execute """
    WITH RECURSIVE path_rebuild AS (
      SELECT id, ARRAY[id]::uuid[] as new_path
      FROM nodes WHERE parent_id IS NULL
      UNION ALL
      SELECT n.id, pr.new_path || n.id
      FROM nodes n
      JOIN path_rebuild pr ON n.parent_id = pr.id
    )
    UPDATE nodes SET path_new = pr.new_path
    FROM path_rebuild pr WHERE nodes.id = pr.id
    """

    # Step 11: Drop old path column, rename new one
    alter table(:nodes) do
      remove :path
    end

    rename table(:nodes), :path_new, to: :path

    # Step 12: Add GIN index on path array for fast lookups
    create index(:nodes, [:path], using: :gin)
  end

  def down do
    # Reverting UUID to integer is complex and destructive
    # Would require regenerating sequential IDs
    raise Ecto.MigrationError, "Cannot revert UUID migration - restore from backup instead"
  end
end
