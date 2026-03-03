defmodule WorkTree.Exchange.Serializer do
  @moduledoc """
  JSON encoding with optional gzip compression for WTXF data.
  """

  @doc """
  Encodes a WTXF map to a JSON string.
  """
  def encode(data) do
    Jason.encode!(data, pretty: true)
  end

  @doc """
  Encodes a WTXF map to JSON and optionally compresses with gzip.
  Returns `{:ok, binary}` or `{:error, reason}`.
  """
  def encode_to_binary(data, opts \\ []) do
    compress = Keyword.get(opts, :compress, false)
    json = encode(data)

    if compress do
      {:ok, :zlib.gzip(json)}
    else
      {:ok, json}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Decodes a JSON string (or gzipped binary) to a map.
  """
  def decode(binary) when is_binary(binary) do
    binary
    |> maybe_decompress()
    |> Jason.decode()
  end

  defp maybe_decompress(<<0x1F, 0x8B, _rest::binary>> = gzipped) do
    :zlib.gunzip(gzipped)
  end

  defp maybe_decompress(plain), do: plain
end
