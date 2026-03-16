defmodule RioWeb.Components.TodoFilterModalComponent do
  @moduledoc """
  Modal component for filtering and viewing uncompleted todos.
  Displays todos sorted by priority and due date urgency.
  """
  use RioWeb, :html

  alias RioWeb.MindMapLive.Helpers
  import RioWeb.Components.SharedComponents

  attr :todo_filter_open, :boolean, required: true
  attr :todo_filter_results, :list, required: true
  attr :todo_filter_selected_index, :integer, required: true
  attr :todo_filter_scope, :atom, required: true
  attr :todo_filter_show_completed, :boolean, required: true

  def todo_filter_modal(assigns) do
    ~H"""
    <div
      :if={@todo_filter_open}
      id="todo-filter-modal-backdrop"
      class="search-modal-backdrop"
      phx-window-keydown={JS.push("close_todo_filter")}
      phx-key="Escape"
    >
      <div
        id="todo-filter-modal"
        class="search-modal"
        phx-click-away="close_todo_filter"
        phx-hook="TodoFilterModal"
      >
        <div class="todo-filter-header">
          <div class="todo-filter-title">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"
              />
            </svg>
            <span>Todo List</span>
          </div>
          <div class="todo-filter-scope-toggle">
            <button
              type="button"
              class={["scope-btn", @todo_filter_scope == :local && "active"]}
              phx-click="todo_filter_set_scope"
              phx-value-scope="local"
            >
              Subtree
            </button>
            <button
              type="button"
              class={["scope-btn", @todo_filter_scope == :global && "active"]}
              phx-click="todo_filter_set_scope"
              phx-value-scope="global"
            >
              All
            </button>
          </div>
          <button
            type="button"
            class="todo-filter-completed-toggle"
            phx-click="todo_filter_toggle_completed"
          >
            <span class={["todo-toggle-check", @todo_filter_show_completed && "checked"]}>
              <%= if @todo_filter_show_completed do %>
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-3 w-3"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                >
                  <path
                    fill-rule="evenodd"
                    d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                    clip-rule="evenodd"
                  />
                </svg>
              <% end %>
            </span>
            <span>Show Completed</span>
          </button>
          <div class="search-hints">
            <span class="kbd kbd-xs">Esc</span>
          </div>
        </div>

        <div class="search-results">
          <%= if @todo_filter_results == [] do %>
            <div class="search-no-results">
              No {if !@todo_filter_show_completed, do: "uncompleted "}todos in {if @todo_filter_scope ==
                                                                                     :local,
                                                                                   do:
                                                                                     "current subtree",
                                                                                   else: "workspace"}
            </div>
          <% end %>

          <%= for {{node, ancestry}, index} <- Enum.with_index(@todo_filter_results) do %>
            <.todo_result_item
              node={node}
              ancestry={ancestry}
              index={index}
              selected={index == @todo_filter_selected_index}
            />
          <% end %>
        </div>

        <div :if={@todo_filter_results != []} class="search-footer">
          <span><span class="kbd kbd-xs">↑</span><span class="kbd kbd-xs">↓</span> navigate</span>
          <span><span class="kbd kbd-xs">Enter</span> go to node</span>
          <span><span class="kbd kbd-xs">Tab</span> toggle scope</span>
        </div>
      </div>
    </div>
    """
  end

  attr :node, :map, required: true
  attr :ancestry, :list, required: true
  attr :index, :integer, required: true
  attr :selected, :boolean, required: true

  defp todo_result_item(assigns) do
    days = Helpers.days_remaining(assigns.node.due_date)
    assigns = assign(assigns, :days_remaining, days)

    ~H"""
    <button
      type="button"
      class={[
        "search-result-item",
        "todo-result-item",
        @selected && "selected",
        @node.todo_completed && "completed"
      ]}
      phx-click="todo_filter_go_to_result"
      phx-value-index={@index}
      phx-mouseover={JS.push("todo_filter_select_index", value: %{index: @index})}
    >
      <.todo_checkbox completed={@node.todo_completed} />
      <div class="search-result-content">
        <div class={["todo-result-title", @node.todo_completed && "completed"]}>
          {@node.title}
        </div>
        <div :if={@ancestry != []} class="search-result-ancestry">
          {Helpers.format_ancestry(@ancestry)}
        </div>
      </div>
      <div class="search-result-meta todo-result-meta">
        <span
          :if={@node.priority != nil}
          class={["search-result-priority", Helpers.priority_class(@node.priority, :css)]}
        >
          P{@node.priority}
        </span>
        <span
          :if={@node.due_date != nil && !@node.todo_completed}
          class={["todo-result-due-date", Helpers.due_date_class(@node.due_date)]}
        >
          {format_days_remaining(@days_remaining)}
        </span>
      </div>
    </button>
    """
  end

  defp format_days_remaining(nil), do: ""
  defp format_days_remaining(days) when days < 0, do: "#{abs(days)}d overdue"
  defp format_days_remaining(0), do: "Today"
  defp format_days_remaining(1), do: "Tomorrow"
  defp format_days_remaining(days), do: "#{days}d left"
end
