defmodule WorkTree.Repo.Migrations.AddDueDateToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :due_date, :date
    end

    create index(:nodes, [:due_date])
  end
end
