defmodule WorkTree.Repo.Migrations.AddSearchInfrastructure do
  use Ecto.Migration

  def up do
    # Enable the pg_trgm extension for fuzzy search
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # Create a GIN index on the title column for fast trigram searches
    execute """
    CREATE INDEX nodes_title_trgm_idx ON nodes
    USING gin (title gin_trgm_ops)
    """

    # Create a GIN index on the body column for searching in JSON content
    # This uses the jsonb_to_tsvector for full-text search on JSON
    execute """
    CREATE INDEX nodes_body_gin_idx ON nodes
    USING gin (body)
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS nodes_title_trgm_idx"
    execute "DROP INDEX IF EXISTS nodes_body_gin_idx"
    execute "DROP EXTENSION IF EXISTS pg_trgm"
  end
end
