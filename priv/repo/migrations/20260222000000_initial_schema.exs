defmodule Rio.Repo.Migrations.InitialSchema do
  @moduledoc """
  Consolidated SQLite migration that creates the full schema.
  Equivalent to all PostgreSQL migrations combined, adapted for SQLite:
  - UUIDs stored as TEXT (SQLite has no native UUID type)
  - Path stored as TEXT delimited string instead of UUID array
  - No extensions (pg_trgm, uuid-ossp)
  - No GIN indexes
  - JSON stored as TEXT (SQLite json1 extension handles extraction)
  """

  use Ecto.Migration

  def change do
    # --- Nodes table ---
    create table(:nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false
      add :parent_id, references(:nodes, type: :binary_id, on_delete: :delete_all)
      add :title, :string, null: false
      add :body, :text, default: "{}"
      add :is_todo, :boolean, default: false, null: false
      add :todo_completed, :boolean, default: false, null: false
      # Materialized path as delimited string: "/uuid1/uuid2/uuid3/"
      add :path, :text, null: false, default: "/"
      add :position, :integer, null: false, default: 0
      add :depth, :integer, null: false, default: 0
      add :edge_label, :string
      add :priority, :integer
      add :link, :string
      add :due_date, :date
      add :completed_at, :utc_datetime
      add :locked, :boolean, default: false, null: false
      add :deleted_at, :utc_datetime
      add :deletion_batch_id, :binary_id
      add :archived_at, :utc_datetime
      add :archive_batch_id, :binary_id

      timestamps()
    end

    create index(:nodes, [:parent_id])
    create index(:nodes, [:path])
    create index(:nodes, [:deleted_at])
    create index(:nodes, [:deletion_batch_id])
    create index(:nodes, [:priority])
    create index(:nodes, [:archived_at])
    create index(:nodes, [:archive_batch_id])

    # --- Attachments table ---
    create table(:attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :url, :string
      add :file_path, :string
      add :title, :string
      add :metadata, :text, default: "{}"
      add :position, :integer, null: false, default: 0

      timestamps()
    end

    create index(:attachments, [:node_id])

    # --- Node events table ---
    create table(:node_events, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :snapshot, :text, null: false
      add :metadata, :text, default: "{}"

      timestamps(updated_at: false)
    end

    create index(:node_events, [:node_id])
    create index(:node_events, [:event_type])
    create index(:node_events, [:inserted_at])
  end
end
