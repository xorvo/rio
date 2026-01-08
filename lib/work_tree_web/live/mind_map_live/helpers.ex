defmodule WorkTreeWeb.MindMapLive.Helpers do
  @moduledoc """
  Shared helper functions for mind map views and components.
  """

  import Phoenix.Component, only: [assign: 3]
  alias WorkTree.MindMaps
  alias WorkTree.MindMaps.Layout

  # Priority color helpers - different formats for different contexts
  # :css - CSS class names for node styling (priority-p0, priority-p1, etc.)
  # :badge - DaisyUI badge classes (badge-error, badge-warning, etc.)
  # :bg - Background color classes for context menu badges

  @doc """
  Returns the appropriate CSS class for a priority level.

  ## Options
    * `:css` - Returns CSS class like "priority-p0" (default)
    * `:badge` - Returns DaisyUI badge class like "badge-error"
    * `:bg` - Returns background class like "bg-error text-error-content"
  """
  def priority_class(priority, style \\ :css)

  def priority_class(0, :css), do: "priority-p0"
  def priority_class(1, :css), do: "priority-p1"
  def priority_class(2, :css), do: "priority-p2"
  def priority_class(3, :css), do: "priority-p3"
  def priority_class(_, :css), do: ""

  def priority_class(0, :badge), do: "badge-error"
  def priority_class(1, :badge), do: "badge-warning"
  def priority_class(2, :badge), do: "badge-info"
  def priority_class(3, :badge), do: "badge-success"
  def priority_class(_, :badge), do: ""

  def priority_class(0, :bg), do: "bg-error text-error-content"
  def priority_class(1, :bg), do: "bg-warning text-warning-content"
  def priority_class(2, :bg), do: "bg-info text-info-content"
  def priority_class(3, :bg), do: "bg-success text-success-content"
  def priority_class(_, :bg), do: "bg-base-300"

  # Due date helpers

  @doc """
  Calculates the number of days remaining until a due date.
  Returns negative number if overdue.
  """
  def days_remaining(nil), do: nil

  def days_remaining(due_date) when is_struct(due_date, Date) do
    Date.diff(due_date, Date.utc_today())
  end

  @doc """
  Returns CSS class for due date badge based on urgency.
  """
  def due_date_class(nil), do: ""

  def due_date_class(due_date) when is_struct(due_date, Date) do
    days = days_remaining(due_date)
    due_date_class_from_days(days)
  end

  def due_date_class_from_days(nil), do: ""
  def due_date_class_from_days(days) when days < 0, do: "due-overdue"
  def due_date_class_from_days(0), do: "due-today"
  def due_date_class_from_days(days) when days <= 3, do: "due-soon"
  def due_date_class_from_days(days) when days <= 7, do: "due-week"
  def due_date_class_from_days(_days), do: "due-later"

  @doc """
  Formats the due date badge label showing days remaining.
  """
  def format_due_date_badge(nil), do: ""

  def format_due_date_badge(due_date) when is_struct(due_date, Date) do
    days = days_remaining(due_date)

    cond do
      days < 0 -> "#{days}d"
      days == 0 -> "0d"
      true -> "#{days}d"
    end
  end

  @doc """
  Formats a datetime for display.
  """
  def format_date(nil), do: "—"

  def format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  @doc """
  Checks if a node body has meaningful content.
  Body is a JSONB map with optional "content" key.
  """
  def has_body_content?(nil), do: false

  def has_body_content?(%{"content" => content}) when is_binary(content),
    do: String.trim(content) != ""

  def has_body_content?(%{}), do: false
  def has_body_content?(_), do: false

  @doc """
  Truncates body text to a maximum length.
  """
  def truncate_body(nil), do: ""

  def truncate_body(text) when is_binary(text) do
    if String.length(text) > 100 do
      String.slice(text, 0, 100) <> "..."
    else
      text
    end
  end

  def truncate_body(_), do: ""

  @doc """
  Formats an ancestry list for display in search results.
  Shows: first / ... / last two items
  """
  def format_ancestry([]), do: ""

  def format_ancestry(ancestors) when is_list(ancestors) do
    case length(ancestors) do
      1 ->
        Enum.at(ancestors, 0)

      2 ->
        Enum.join(ancestors, " / ")

      _ ->
        first = Enum.at(ancestors, 0)
        last_two = Enum.take(ancestors, -2)
        "#{first} / ... / #{Enum.join(last_two, " / ")}"
    end
  end

  @doc """
  Counts direct children of a node.
  """
  def node_children_count(node, nodes) do
    Enum.count(nodes, &(&1.parent_id == node.id))
  end

  @doc """
  Gets the count of all descendants (children, grandchildren, etc.) of a node.
  Used for the drag badge showing how many nodes will be moved.
  """
  def get_subtree_count(node, nodes) do
    get_descendant_ids(node, nodes) |> length()
  end

  @doc """
  Gets all descendant IDs of a node (for drag validation).
  Returns a list of node IDs that are descendants of the given node.
  """
  def get_descendant_ids(node, nodes) do
    direct_children = Enum.filter(nodes, &(&1.parent_id == node.id))

    Enum.flat_map(direct_children, fn child ->
      [child.id | get_descendant_ids(child, nodes)]
    end)
  end

  @doc """
  Creates a curved bezier path for an edge between nodes.
  """
  def edge_path(edge) do
    mid_x = (edge.source_x + edge.target_x) / 2

    "M #{edge.source_x} #{edge.source_y} C #{mid_x} #{edge.source_y}, #{mid_x} #{edge.target_y}, #{edge.target_x} #{edge.target_y}"
  end

  @doc """
  Highlights text with match ranges for search results.
  """
  def highlight_text(text, []), do: text

  def highlight_text(text, ranges) when is_binary(text) do
    graphemes = String.graphemes(text)
    total_len = length(graphemes)

    # Sort ranges by start position
    sorted_ranges = Enum.sort_by(ranges, fn {start, _stop} -> start end)

    # Build segments with highlight info
    {segments, last_pos} =
      Enum.reduce(sorted_ranges, {[], 0}, fn {start, stop}, {acc, pos} ->
        # Clamp positions to valid range
        start = max(0, min(start, total_len))
        stop = max(0, min(stop, total_len))

        if start >= stop or start < pos do
          {acc, pos}
        else
          # Add non-highlighted segment before this range
          before =
            if start > pos do
              [{:text, Enum.slice(graphemes, pos, start - pos) |> Enum.join()}]
            else
              []
            end

          # Add highlighted segment
          highlighted = [{:highlight, Enum.slice(graphemes, start, stop - start) |> Enum.join()}]

          {acc ++ before ++ highlighted, stop}
        end
      end)

    # Add remaining text after last highlight
    final_segments =
      if last_pos < total_len do
        segments ++
          [{:text, Enum.slice(graphemes, last_pos, total_len - last_pos) |> Enum.join()}]
      else
        segments
      end

    # Convert to Phoenix HTML
    Phoenix.HTML.raw(
      Enum.map(final_segments, fn
        {:text, str} ->
          Phoenix.HTML.html_escape(str) |> Phoenix.HTML.safe_to_string()

        {:highlight, str} ->
          "<mark class=\"search-highlight\">#{Phoenix.HTML.html_escape(str) |> Phoenix.HTML.safe_to_string()}</mark>"
      end)
      |> Enum.join()
    )
  end

  @doc """
  Reloads the tree data and recalculates layout.
  Used after any operation that modifies the tree structure.
  Respects the :show_archived setting from socket assigns.
  """
  def reload_tree(socket) do
    root = MindMaps.get_node!(socket.assigns.root.id)
    show_archived = Map.get(socket.assigns, :show_archived, false)
    tree = MindMaps.get_subtree(root, show_archived: show_archived)
    node_positions = Layout.calculate_positions(tree)
    edges = Layout.calculate_edges(tree, node_positions)
    nodes = Layout.flatten_tree(tree)
    {_min_x, _min_y, max_x, max_y} = Layout.bounding_box(node_positions)

    socket
    |> assign(:root, root)
    |> assign(:tree, tree)
    |> assign(:node_positions, node_positions)
    |> assign(:edges, edges)
    |> assign(:nodes, nodes)
    |> assign(:canvas_width, max_x + 100)
    |> assign(:canvas_height, max_y + 100)
  end
end
