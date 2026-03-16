defmodule RioWeb.MindMapLive.TodoFilterHandlers do
  @moduledoc """
  Event handlers for the todo filter modal.
  Handles filtering, sorting, and navigation of uncompleted todos.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, push_event: 3]

  alias Rio.MindMaps

  @doc """
  Opens the todo filter modal and loads filtered results.
  Preserves the user's last scope preference.
  """
  def open_todo_filter(socket) do
    scope = socket.assigns.todo_filter_scope
    show_completed = socket.assigns.todo_filter_show_completed
    socket = load_todo_results(socket, scope, show_completed)

    {:noreply,
     socket
     |> assign(:todo_filter_open, true)
     |> assign(:todo_filter_selected_index, 0)}
  end

  @doc """
  Closes the todo filter modal and clears results.
  """
  def close_todo_filter(socket) do
    {:noreply,
     socket
     |> assign(:todo_filter_open, false)
     |> assign(:todo_filter_results, [])
     |> assign(:todo_filter_selected_index, 0)}
  end

  @doc """
  Toggles between local (subtree) and global scope.
  Reloads results with the new scope and persists the preference.
  """
  def toggle_scope(socket) do
    new_scope = if socket.assigns.todo_filter_scope == :local, do: :global, else: :local
    show_completed = socket.assigns.todo_filter_show_completed
    socket = load_todo_results(socket, new_scope, show_completed)

    {:noreply,
     socket
     |> assign(:todo_filter_scope, new_scope)
     |> assign(:todo_filter_selected_index, 0)}
  end

  @doc """
  Sets the scope directly (used by UI buttons).
  """
  def set_scope(socket, scope) when scope in [:local, :global] do
    if socket.assigns.todo_filter_scope == scope do
      {:noreply, socket}
    else
      show_completed = socket.assigns.todo_filter_show_completed
      socket = load_todo_results(socket, scope, show_completed)

      {:noreply,
       socket
       |> assign(:todo_filter_scope, scope)
       |> assign(:todo_filter_selected_index, 0)}
    end
  end

  @doc """
  Toggles showing completed todos.
  """
  def toggle_show_completed(socket) do
    new_show_completed = !socket.assigns.todo_filter_show_completed
    scope = socket.assigns.todo_filter_scope
    socket = load_todo_results(socket, scope, new_show_completed)

    {:noreply,
     socket
     |> assign(:todo_filter_show_completed, new_show_completed)
     |> assign(:todo_filter_selected_index, 0)}
  end

  @doc """
  Selects the previous result (wraps around).
  """
  def select_prev(socket) do
    current = socket.assigns.todo_filter_selected_index
    results_count = length(socket.assigns.todo_filter_results)

    new_index =
      if results_count > 0 do
        rem(current - 1 + results_count, results_count)
      else
        0
      end

    {:noreply, assign(socket, :todo_filter_selected_index, new_index)}
  end

  @doc """
  Selects the next result (wraps around).
  """
  def select_next(socket) do
    current = socket.assigns.todo_filter_selected_index
    results_count = length(socket.assigns.todo_filter_results)

    new_index =
      if results_count > 0 do
        rem(current + 1, results_count)
      else
        0
      end

    {:noreply, assign(socket, :todo_filter_selected_index, new_index)}
  end

  @doc """
  Sets the selected index directly (e.g., on mouse hover).
  """
  def select_index(socket, index) do
    index = if is_binary(index), do: String.to_integer(index), else: index
    {:noreply, assign(socket, :todo_filter_selected_index, index)}
  end

  @doc """
  Navigates to the result at the given index.
  """
  def go_to_result(socket, index) do
    index = if is_binary(index), do: String.to_integer(index), else: index
    do_go_to_result(socket, index)
  end

  @doc """
  Confirms selection and navigates to the currently selected result.
  """
  def confirm_selection(socket) do
    index = socket.assigns.todo_filter_selected_index
    do_go_to_result(socket, index)
  end

  # Private helpers

  defp load_todo_results(socket, scope, show_completed) do
    all_nodes =
      case scope do
        :local -> socket.assigns.nodes
        :global -> MindMaps.get_all_nodes()
      end

    # Filter todos based on show_completed setting
    filtered_todos =
      Enum.filter(all_nodes, fn node ->
        node.is_todo && (show_completed || !node.todo_completed)
      end)

    # Sort by priority (ascending, nil last) then by due date (closest first, nil last)
    sorted_todos = sort_todos(filtered_todos)

    # Build ancestry for each todo (pass all_nodes to avoid duplicate query)
    ancestry_map = build_ancestry_map(all_nodes, socket.assigns.root.id)

    results =
      Enum.map(sorted_todos, fn node ->
        ancestry = Map.get(ancestry_map, node.id, [])
        {node, ancestry}
      end)

    assign(socket, :todo_filter_results, results)
  end

  defp sort_todos(todos) do
    Enum.sort_by(todos, fn node ->
      priority_score =
        case node.priority do
          nil -> 999
          p -> p
        end

      due_date_score =
        case node.due_date do
          nil -> ~D[9999-12-31]
          date -> date
        end

      {priority_score, due_date_score}
    end)
  end

  defp build_ancestry_map(all_nodes, root_id) do
    all_nodes_by_id = Map.new(all_nodes, &{&1.id, &1})

    Enum.reduce(all_nodes, %{}, fn node, acc ->
      ancestry = get_ancestry(node, all_nodes_by_id, root_id)
      Map.put(acc, node.id, ancestry)
    end)
  end

  defp get_ancestry(node, nodes_by_id, root_id) do
    get_ancestry_recursive(node.parent_id, nodes_by_id, root_id, [])
  end

  defp get_ancestry_recursive(nil, _nodes_by_id, _root_id, acc), do: Enum.reverse(acc)

  defp get_ancestry_recursive(parent_id, nodes_by_id, root_id, acc) do
    case Map.get(nodes_by_id, parent_id) do
      nil ->
        Enum.reverse(acc)

      parent ->
        new_acc = [parent.title | acc]

        if parent.id == root_id do
          Enum.reverse(new_acc)
        else
          get_ancestry_recursive(parent.parent_id, nodes_by_id, root_id, new_acc)
        end
    end
  end

  defp do_go_to_result(socket, index) do
    case Enum.at(socket.assigns.todo_filter_results, index) do
      {node, _ancestry} ->
        # Focus on the parent node instead of the todo itself,
        # since todos are typically leaf nodes and the user wants to see context
        focus_id = node.parent_id || node.id
        local_node_ids = MapSet.new(socket.assigns.nodes, & &1.id)
        is_local = MapSet.member?(local_node_ids, focus_id)

        if is_local do
          {:noreply,
           socket
           |> assign(:todo_filter_open, false)
           |> assign(:todo_filter_results, [])
           |> assign(:todo_filter_selected_index, 0)
           |> assign(:focused_node_id, focus_id)
           |> push_event("scroll-to-node", %{id: focus_id})}
        else
          {:noreply,
           socket
           |> assign(:todo_filter_open, false)
           |> assign(:todo_filter_results, [])
           |> assign(:todo_filter_selected_index, 0)
           |> push_navigate(to: "/node/#{focus_id}")}
        end

      nil ->
        {:noreply, socket}
    end
  end
end
