defmodule WorkTree.FuzzySearch do
  @moduledoc """
  Fuzzy search implementation for matching nodes by title and body content.

  Scoring algorithm:
  - Title exact match (case-insensitive): 100 points
  - Title starts with query: 80 points
  - Title word starts with query: 60 points
  - Title contains query: 40 points
  - Body contains query: 20 points
  - Consecutive character matches bonus
  - Earlier match position bonus
  """

  alias WorkTree.MindMaps

  @doc """
  Search nodes using fuzzy matching and return scored results.

  Returns a list of {node, score, highlights, ancestry} tuples sorted by score descending.
  Only returns results with score > 0.

  Options:
  - :ancestry_map - A map of node_id => [ancestor_titles] for showing ancestry hints
  """
  def search(nodes, query, opts \\ []) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      []
    else
      ancestry_map = Keyword.get(opts, :ancestry_map, %{})
      query_lower = String.downcase(query)
      query_chars = String.graphemes(query_lower)

      nodes
      |> Enum.map(fn node ->
        {node, score, highlights} = score_node(node, query_lower, query_chars)
        ancestry = Map.get(ancestry_map, node.id, [])
        {node, score, highlights, ancestry}
      end)
      |> Enum.filter(fn {_node, score, _highlights, _ancestry} -> score > 0 end)
      |> Enum.sort_by(fn {_node, score, _highlights, _ancestry} -> score end, :desc)
      |> Enum.take(20)
    end
  end

  @doc """
  Builds an ancestry map for a list of nodes.
  Returns a map of node_id => [ancestor_titles] (from root to parent).
  """
  def build_ancestry_map(nodes) do
    nodes
    |> Enum.map(fn node ->
      ancestors = MindMaps.get_ancestors(node)
      ancestor_titles = Enum.map(ancestors, & &1.title)
      {node.id, ancestor_titles}
    end)
    |> Map.new()
  end

  defp score_node(node, query_lower, query_chars) do
    title = node.title || ""
    title_lower = String.downcase(title)

    body_text = extract_body_text(node.body)
    body_lower = String.downcase(body_text)

    {title_score, title_highlights} = score_field(title, title_lower, query_lower, query_chars, :title)
    {body_score, body_highlights} = score_field(body_text, body_lower, query_lower, query_chars, :body)

    total_score = title_score + body_score

    highlights = %{
      title: title_highlights,
      body: body_highlights
    }

    {node, total_score, highlights}
  end

  defp score_field(text, text_lower, query_lower, query_chars, field_type) do
    base_multiplier = if field_type == :title, do: 1.0, else: 0.5

    cond do
      # Exact match
      text_lower == query_lower ->
        {round(100 * base_multiplier), [{0, String.length(text)}]}

      # Starts with query
      String.starts_with?(text_lower, query_lower) ->
        {round(80 * base_multiplier), [{0, String.length(query_lower)}]}

      # Word starts with query
      word_start_match?(text_lower, query_lower) ->
        pos = find_word_start_position(text_lower, query_lower)
        {round(60 * base_multiplier), [{pos, pos + String.length(query_lower)}]}

      # Contains query as substring
      String.contains?(text_lower, query_lower) ->
        pos = find_substring_position(text_lower, query_lower)
        {round(40 * base_multiplier), [{pos, pos + String.length(query_lower)}]}

      # Fuzzy character match
      true ->
        case fuzzy_match(text_lower, query_chars) do
          {:ok, positions, score} ->
            highlights = positions_to_ranges(positions)
            {round(score * base_multiplier), highlights}
          :no_match ->
            {0, []}
        end
    end
  end

  defp word_start_match?(text_lower, query_lower) do
    # Check if any word in the text starts with the query
    text_lower
    |> String.split(~r/[\s\-_]+/)
    |> Enum.any?(fn word -> String.starts_with?(word, query_lower) end)
  end

  defp find_word_start_position(text_lower, query_lower) do
    # Find the position where a word starts with the query
    case Regex.run(~r/(?:^|[\s\-_])#{Regex.escape(query_lower)}/, text_lower, return: :index) do
      [{start, _len}] ->
        # Adjust for the separator character if not at start
        if start > 0, do: start + 1, else: start
      _ ->
        0
    end
  end

  defp find_substring_position(text_lower, query_lower) do
    case :binary.match(text_lower, query_lower) do
      {pos, _len} -> pos
      :nomatch -> 0
    end
  end

  @doc """
  Fuzzy match using character sequence matching.
  Returns {:ok, positions, score} or :no_match.

  The algorithm finds the best sequence of characters that match the query,
  preferring consecutive matches and matches at word boundaries.
  """
  def fuzzy_match(text, query_chars) when is_list(query_chars) do
    text_chars = String.graphemes(text)

    case find_char_positions(text_chars, query_chars, 0, []) do
      {:ok, positions} ->
        score = calculate_fuzzy_score(positions, length(text_chars), length(query_chars))
        {:ok, Enum.reverse(positions), score}
      :no_match ->
        :no_match
    end
  end

  defp find_char_positions(_text_chars, [], _index, acc), do: {:ok, acc}
  defp find_char_positions([], _query_chars, _index, _acc), do: :no_match

  defp find_char_positions([tc | text_rest], [qc | query_rest] = query_chars, index, acc) do
    if tc == qc do
      find_char_positions(text_rest, query_rest, index + 1, [index | acc])
    else
      find_char_positions(text_rest, query_chars, index + 1, acc)
    end
  end

  defp calculate_fuzzy_score(positions, text_length, query_length) do
    # Base score for matching all characters
    base_score = 20

    # Bonus for consecutive matches
    consecutive_bonus =
      positions
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.count(fn [a, b] -> b == a + 1 end)
      |> then(fn count -> count * 3 end)

    # Bonus for matches at the start
    start_bonus =
      if Enum.any?(positions, &(&1 == 0)), do: 10, else: 0

    # Penalty for long strings (prefer shorter matches)
    length_penalty = min(5, div(text_length, 10))

    # Bonus for higher match density
    density_bonus =
      if text_length > 0 do
        round((query_length / text_length) * 10)
      else
        0
      end

    base_score + consecutive_bonus + start_bonus + density_bonus - length_penalty
  end

  defp positions_to_ranges(positions) do
    # Convert individual positions to contiguous ranges
    positions
    |> Enum.sort()
    |> Enum.reduce([], fn pos, acc ->
      case acc do
        [{start, stop} | rest] when pos == stop ->
          [{start, pos + 1} | rest]
        _ ->
          [{pos, pos + 1} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp extract_body_text(nil), do: ""
  defp extract_body_text(body) when is_map(body) do
    case body do
      %{"content" => content} when is_binary(content) -> content
      %{"text" => text} when is_binary(text) -> text
      _ -> ""
    end
  end
  defp extract_body_text(_), do: ""
end
