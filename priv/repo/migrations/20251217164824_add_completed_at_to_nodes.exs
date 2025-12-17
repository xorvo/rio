defmodule WorkTree.Repo.Migrations.AddCompletedAtToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :completed_at, :utc_datetime
    end
  end
end
