defmodule WorkTree.Ecto.PathType do
  @moduledoc """
  Custom Ecto type that stores materialized paths.

  - PostgreSQL: stored as a UUID array (`uuid[]`)
  - SQLite: stored as a delimited string (`"/uuid1/uuid2/"`)

  In Elixir, the value is always a list of UUID strings.
  """

  use Ecto.Type

  def type do
    if WorkTree.DB.sqlite?() do
      :string
    else
      {:array, Ecto.UUID}
    end
  end

  # Cast from external input (e.g. changeset params)
  def cast(path) when is_list(path), do: {:ok, path}

  def cast(path) when is_binary(path) do
    {:ok, WorkTree.DB.deserialize_path(path)}
  end

  def cast(nil), do: {:ok, []}
  def cast(_), do: :error

  # Load from the database
  def load(path) when is_list(path), do: {:ok, path}

  def load(path) when is_binary(path) do
    {:ok, WorkTree.DB.deserialize_path(path)}
  end

  def load(nil), do: {:ok, []}
  def load(_), do: :error

  # Dump to the database
  def dump(path) when is_list(path) do
    {:ok, WorkTree.DB.serialize_path(path)}
  end

  def dump(nil), do: {:ok, WorkTree.DB.serialize_path([])}
  def dump(_), do: :error

  def embed_as(_format), do: :self

  def equal?(a, b), do: a == b
end
