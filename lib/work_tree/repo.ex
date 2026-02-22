defmodule WorkTree.Repo do
  use Ecto.Repo,
    otp_app: :work_tree,
    adapter:
      if(System.get_env("WORK_TREE_DESKTOP") == "true",
        do: Ecto.Adapters.SQLite3,
        else: Ecto.Adapters.Postgres
      )

  @impl true
  def init(_type, config) do
    {:ok, Keyword.put(config, :migration_primary_key, type: :binary_id)}
  end
end
