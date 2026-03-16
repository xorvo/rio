defmodule Rio.Repo.Migrations.AddFts5 do
  @moduledoc """
  Adds FTS5 full-text search index on nodes for fast title and body search.
  Uses content-sync triggers to keep the FTS index up to date automatically.
  """

  use Ecto.Migration

  def up do
    # Create the FTS5 virtual table backed by the nodes table
    execute("""
    CREATE VIRTUAL TABLE nodes_fts USING fts5(
      title,
      body_text,
      content='nodes',
      content_rowid='rowid',
      tokenize='unicode61'
    )
    """)

    # Populate the FTS index from existing data
    execute("""
    INSERT INTO nodes_fts(rowid, title, body_text)
    SELECT rowid, title, json_extract(body, '$.content') FROM nodes
    """)

    # Trigger: keep FTS in sync after INSERT
    execute("""
    CREATE TRIGGER nodes_ai AFTER INSERT ON nodes BEGIN
      INSERT INTO nodes_fts(rowid, title, body_text)
      VALUES (new.rowid, new.title, json_extract(new.body, '$.content'));
    END
    """)

    # Trigger: keep FTS in sync after DELETE
    execute("""
    CREATE TRIGGER nodes_ad AFTER DELETE ON nodes BEGIN
      INSERT INTO nodes_fts(nodes_fts, rowid, title, body_text)
      VALUES ('delete', old.rowid, old.title, json_extract(old.body, '$.content'));
    END
    """)

    # Trigger: keep FTS in sync after UPDATE
    execute("""
    CREATE TRIGGER nodes_au AFTER UPDATE ON nodes BEGIN
      INSERT INTO nodes_fts(nodes_fts, rowid, title, body_text)
      VALUES ('delete', old.rowid, old.title, json_extract(old.body, '$.content'));
      INSERT INTO nodes_fts(rowid, title, body_text)
      VALUES (new.rowid, new.title, json_extract(new.body, '$.content'));
    END
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS nodes_au")
    execute("DROP TRIGGER IF EXISTS nodes_ad")
    execute("DROP TRIGGER IF EXISTS nodes_ai")
    execute("DROP TABLE IF EXISTS nodes_fts")
  end
end
