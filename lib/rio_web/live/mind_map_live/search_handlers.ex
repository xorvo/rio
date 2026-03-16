defmodule RioWeb.MindMapLive.SearchHandlers do
  @moduledoc """
  Search-related event handlers for the mind map LiveView.
  Handles search modal interactions, query processing, and result navigation.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, push_event: 3]

  alias Rio.MindMaps
  alias Rio.FuzzySearch

  @doc """
  Opens the search modal and resets search state.
  """
  def open_search(socket) do
    {:noreply,
     socket
     |> assign(:search_open, true)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:global_search_results, [])
     |> assign(:search_selected_index, 0)}
  end

  @doc """
  Closes the search modal and clears search state.
  """
  def close_search(socket) do
    {:noreply,
     socket
     |> assign(:search_open, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:global_search_results, [])
     |> assign(:search_selected_index, 0)}
  end

  @doc """
  Handles search query input and performs fuzzy search.
  Searches both local subtree and global nodes.
  """
  def handle_search(socket, %{"query" => query}) do
    query = String.trim(query)

    if query == "" do
      {:noreply,
       socket
       |> assign(:search_query, "")
       |> assign(:search_results, [])
       |> assign(:global_search_results, [])
       |> assign(:search_selected_index, 0)}
    else
      # Build ancestry map for local nodes
      local_nodes = socket.assigns.nodes
      local_ancestry_map = FuzzySearch.build_ancestry_map(local_nodes)
      local_results = FuzzySearch.search(local_nodes, query, ancestry_map: local_ancestry_map)
      local_node_ids = MapSet.new(local_nodes, & &1.id)

      # Get global nodes (excluding local subtree)
      all_nodes = MindMaps.get_all_nodes()

      global_nodes =
        Enum.reject(all_nodes, fn node -> MapSet.member?(local_node_ids, node.id) end)

      global_ancestry_map = FuzzySearch.build_ancestry_map(global_nodes)
      global_results = FuzzySearch.search(global_nodes, query, ancestry_map: global_ancestry_map)

      {:noreply,
       socket
       |> assign(:search_query, query)
       |> assign(:search_results, local_results)
       |> assign(:global_search_results, global_results)
       |> assign(:search_selected_index, 0)}
    end
  end

  @doc """
  Selects the previous search result (wraps around).
  """
  def select_prev(socket) do
    current = socket.assigns.search_selected_index
    results_count = total_search_results_count(socket)

    new_index =
      if results_count > 0 do
        rem(current - 1 + results_count, results_count)
      else
        0
      end

    {:noreply, select_and_preview(socket, new_index)}
  end

  @doc """
  Selects the next search result (wraps around).
  """
  def select_next(socket) do
    current = socket.assigns.search_selected_index
    results_count = total_search_results_count(socket)

    new_index =
      if results_count > 0 do
        rem(current + 1, results_count)
      else
        0
      end

    {:noreply, select_and_preview(socket, new_index)}
  end

  @doc """
  Sets the selected index directly (e.g., on mouse hover).
  """
  def select_index(socket, index) do
    index = if is_binary(index), do: String.to_integer(index), else: index
    {:noreply, assign(socket, :search_selected_index, index)}
  end

  @doc """
  Navigates to the search result at the given index.
  """
  def go_to_result(socket, index) do
    index = if is_binary(index), do: String.to_integer(index), else: index
    do_go_to_result(socket, index)
  end

  @doc """
  Confirms selection and navigates to the currently selected result.
  """
  def confirm_selection(socket) do
    index = socket.assigns.search_selected_index
    do_go_to_result(socket, index)
  end

  # Private helpers

  defp total_search_results_count(socket) do
    length(socket.assigns.search_results) + length(socket.assigns.global_search_results)
  end

  defp get_search_result_at(socket, index) do
    local_results = socket.assigns.search_results
    local_count = length(local_results)

    if index < local_count do
      Enum.at(local_results, index)
    else
      global_index = index - local_count
      Enum.at(socket.assigns.global_search_results, global_index)
    end
  end

  defp select_and_preview(socket, index) do
    socket = assign(socket, :search_selected_index, index)

    case get_search_result_at(socket, index) do
      {node, _score, _highlights, _ancestry} ->
        local_node_ids = MapSet.new(socket.assigns.nodes, & &1.id)

        if MapSet.member?(local_node_ids, node.id) do
          push_event(socket, "scroll-to-node", %{id: node.id})
        else
          socket
        end

      nil ->
        socket
    end
  end

  defp do_go_to_result(socket, index) do
    case get_search_result_at(socket, index) do
      {node, _score, _highlights, _ancestry} ->
        local_node_ids = MapSet.new(socket.assigns.nodes, & &1.id)
        is_local = MapSet.member?(local_node_ids, node.id)

        socket =
          socket
          |> assign(:search_open, false)
          |> assign(:search_query, "")
          |> assign(:search_results, [])
          |> assign(:global_search_results, [])
          |> assign(:search_selected_index, 0)

        if is_local do
          {:noreply,
           socket
           |> assign(:focused_node_id, node.id)
           |> push_event("center-node", %{id: node.id})}
        else
          # Navigate to the parent's subtree so the node is visible in context
          target_id = node.parent_id || node.id
          {:noreply, push_navigate(socket, to: "/node/#{target_id}?focus=#{node.id}")}
        end

      nil ->
        {:noreply, socket}
    end
  end
end
