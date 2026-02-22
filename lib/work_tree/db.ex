defmodule WorkTree.DB do
  @moduledoc """
  Cross-database compatibility helpers.
  Dispatches query fragments based on the configured storage backend (:postgres or :sqlite).
  """

  @doc """
  Returns the configured storage backend (:postgres or :sqlite).
  """
  def backend do
    Application.get_env(:work_tree, :storage_backend, :postgres)
  end

  @doc """
  Returns true if using SQLite backend.
  """
  def sqlite?, do: backend() == :sqlite

  @doc """
  Returns true if using PostgreSQL backend.
  """
  def postgres?, do: backend() == :postgres

  @doc """
  Serializes a path list to the storage format.
  PostgreSQL: keeps as list (UUID array)
  SQLite: joins to delimited string "/uuid1/uuid2/uuid3/"
  """
  def serialize_path(path) when is_list(path) do
    if sqlite?() do
      "/" <> Enum.join(path, "/") <> "/"
    else
      path
    end
  end

  @doc """
  Deserializes a path from storage format to a list of UUIDs.
  """
  def deserialize_path(path) when is_list(path), do: path

  def deserialize_path(path) when is_binary(path) do
    path
    |> String.trim("/")
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
  end

  def deserialize_path(nil), do: []
end
