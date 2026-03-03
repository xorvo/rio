defmodule WorkTree.Ecto.PathType do
  @moduledoc """
  Custom Ecto type that stores materialized paths.

  Stored as a delimited string (`"/uuid1/uuid2/"`) in SQLite.
  In Elixir, the value is always a list of UUID strings.
  """

  use Ecto.Type

  def type, do: :string

  # Cast from external input (e.g. changeset params)
  def cast(path) when is_list(path), do: {:ok, path}

  def cast(path) when is_binary(path) do
    {:ok, deserialize_path(path)}
  end

  def cast(nil), do: {:ok, []}
  def cast(_), do: :error

  # Load from the database
  def load(path) when is_list(path), do: {:ok, path}

  def load(path) when is_binary(path) do
    {:ok, deserialize_path(path)}
  end

  def load(nil), do: {:ok, []}
  def load(_), do: :error

  # Dump to the database
  def dump(path) when is_list(path) do
    {:ok, serialize_path(path)}
  end

  def dump(nil), do: {:ok, serialize_path([])}
  def dump(_), do: :error

  def embed_as(_format), do: :self

  def equal?(a, b), do: a == b

  @doc """
  Serializes a path list to delimited string format: "/uuid1/uuid2/uuid3/"
  """
  def serialize_path(path) when is_list(path) do
    "/" <> Enum.join(path, "/") <> "/"
  end

  @doc """
  Deserializes a path from delimited string format to a list of UUIDs.
  """
  def deserialize_path(path) when is_binary(path) do
    path
    |> String.trim("/")
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
  end

  def deserialize_path(path) when is_list(path), do: path
  def deserialize_path(nil), do: []
end
