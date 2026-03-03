defmodule WorkTree.Repo do
  use Ecto.Repo,
    otp_app: :work_tree,
    adapter: Ecto.Adapters.SQLite3

  @impl true
  def init(_type, config) do
    {:ok, Keyword.put(config, :migration_primary_key, type: :binary_id)}
  end
end
