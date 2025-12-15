defmodule WorkTree.Repo.Migrations.AddPriorityToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      # Priority uses numeric scale: p0 = highest priority, p1, p2, etc.
      # NULL means no priority set
      add :priority, :integer
    end

    create index(:nodes, [:priority])
  end
end
