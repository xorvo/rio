defmodule WorkTree.Repo.Migrations.AddLockedToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :locked, :boolean, default: false, null: false
    end

    create index(:nodes, [:locked], where: "locked = true")
  end
end
