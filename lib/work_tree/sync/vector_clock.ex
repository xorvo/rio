defmodule WorkTree.Sync.VectorClock do
  @moduledoc """
  Vector clock operations for causal ordering of sync events.

  A vector clock is a map of `%{device_id => sequence_number}` that
  tracks the last known sequence from each device.
  """

  @type t :: %{String.t() => non_neg_integer()}

  @doc """
  Creates a new empty vector clock.
  """
  def new, do: %{}

  @doc """
  Increments the sequence for the given device.
  """
  def increment(clock, device_id) do
    Map.update(clock, device_id, 1, &(&1 + 1))
  end

  @doc """
  Returns the current sequence number for a device.
  """
  def get(clock, device_id) do
    Map.get(clock, device_id, 0)
  end

  @doc """
  Merges two vector clocks by taking the max of each device's sequence.
  """
  def merge(clock_a, clock_b) do
    Map.merge(clock_a, clock_b, fn _device, seq_a, seq_b ->
      max(seq_a, seq_b)
    end)
  end

  @doc """
  Returns true if clock_a dominates clock_b (all entries >= and at least one >).
  """
  def dominates?(clock_a, clock_b) do
    all_devices = Map.keys(clock_a) ++ Map.keys(clock_b) |> Enum.uniq()

    all_gte =
      Enum.all?(all_devices, fn d ->
        get(clock_a, d) >= get(clock_b, d)
      end)

    any_gt =
      Enum.any?(all_devices, fn d ->
        get(clock_a, d) > get(clock_b, d)
      end)

    all_gte and any_gt
  end

  @doc """
  Returns true if the clocks are concurrent (neither dominates).
  """
  def concurrent?(clock_a, clock_b) do
    not dominates?(clock_a, clock_b) and not dominates?(clock_b, clock_a) and clock_a != clock_b
  end

  @doc """
  Encodes a vector clock to a JSON string for storage.
  """
  def encode(clock) do
    Jason.encode!(clock)
  end

  @doc """
  Decodes a vector clock from a JSON string.
  """
  def decode(nil), do: new()
  def decode(""), do: new()

  def decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, clock} when is_map(clock) -> clock
      _ -> new()
    end
  end

  def decode(clock) when is_map(clock), do: clock
end
