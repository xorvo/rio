defmodule WorkTree.Repo do
  use Ecto.Repo,
    otp_app: :work_tree,
    adapter: Ecto.Adapters.Postgres
end
