defmodule WorkTree.Repo.Migrations.AddLinkToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :link, :string
    end
  end
end
