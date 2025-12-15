defmodule MindMapperPoc.Repo do
  use Ecto.Repo,
    otp_app: :mind_mapper_poc,
    adapter: Ecto.Adapters.Postgres
end
