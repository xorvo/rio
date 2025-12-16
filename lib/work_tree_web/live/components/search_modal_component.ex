defmodule WorkTreeWeb.Components.SearchModalComponent do
  @moduledoc """
  Command palette style search modal for finding nodes.
  Displays both local subtree and global search results.
  """
  use WorkTreeWeb, :html

  alias WorkTreeWeb.MindMapLive.Helpers

  attr :search_open, :boolean, required: true
  attr :search_query, :string, required: true
  attr :search_results, :list, required: true
  attr :global_search_results, :list, required: true
  attr :search_selected_index, :integer, required: true

  def search_modal(assigns) do
    ~H"""
    <div
      :if={@search_open}
      id="search-modal-backdrop"
      class="search-modal-backdrop"
      phx-click="close_search"
      phx-window-keydown={JS.push("close_search")}
      phx-key="Escape"
    >
      <div
        id="search-modal"
        class="search-modal"
        phx-click-away="close_search"
        phx-hook="SearchModal"
      >
        <form phx-change="search" phx-submit="search_confirm" class="search-input-wrapper">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="search-icon"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
            />
          </svg>
          <input
            type="text"
            id="search-input"
            name="query"
            value={@search_query}
            placeholder="Search nodes..."
            class="search-input"
            phx-debounce="100"
            autocomplete="off"
            autofocus
          />
          <div class="search-hints">
            <span class="kbd kbd-xs">Esc</span>
          </div>
        </form>

        <div class="search-results">
          <%= if @search_query != "" and @search_results == [] and @global_search_results == [] do %>
            <div class="search-no-results">
              No nodes found matching "{@search_query}"
            </div>
          <% end %>

          <%!-- Local (current subtree) results --%>
          <div :if={@search_results != []} class="search-section-header">
            Current subtree
          </div>
          <%= for {{node, _score, highlights, ancestry}, index} <- Enum.with_index(@search_results) do %>
            <.search_result_item
              node={node}
              highlights={highlights}
              ancestry={ancestry}
              index={index}
              selected={index == @search_selected_index}
            />
          <% end %>

          <%!-- Global results --%>
          <div :if={@global_search_results != []} class="search-section-header">
            Other nodes
          </div>
          <% local_count = length(@search_results) %>
          <%= for {{node, _score, highlights, ancestry}, idx} <- Enum.with_index(@global_search_results) do %>
            <% index = local_count + idx %>
            <.search_result_item
              node={node}
              highlights={highlights}
              ancestry={ancestry}
              index={index}
              selected={index == @search_selected_index}
            />
          <% end %>
        </div>

        <div :if={@search_results != [] or @global_search_results != []} class="search-footer">
          <span><span class="kbd kbd-xs">↑</span><span class="kbd kbd-xs">↓</span> navigate</span>
          <span><span class="kbd kbd-xs">Enter</span> go to node</span>
        </div>
      </div>
    </div>
    """
  end

  attr :node, :map, required: true
  attr :highlights, :map, required: true
  attr :ancestry, :list, required: true
  attr :index, :integer, required: true
  attr :selected, :boolean, required: true

  defp search_result_item(assigns) do
    ~H"""
    <button
      type="button"
      class={["search-result-item", @selected && "selected"]}
      phx-click="search_go_to_result"
      phx-value-index={@index}
      phx-mouseover={JS.push("search_select_index", value: %{index: @index})}
    >
      <div class="search-result-content">
        <div class="search-result-title">
          <span :if={@node.is_todo} class="search-result-todo">
            <%= if @node.todo_completed do %>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
              </svg>
            <% else %>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <circle cx="12" cy="12" r="9" stroke-width="2" />
              </svg>
            <% end %>
          </span>
          <%= if @highlights.title != [] do %>
            {Helpers.highlight_text(@node.title, @highlights.title)}
          <% else %>
            {@node.title}
          <% end %>
        </div>
        <div :if={@ancestry != []} class="search-result-ancestry">
          {Helpers.format_ancestry(@ancestry)}
        </div>
        <div :if={@node.body["content"]} class="search-result-body">
          <%= if @highlights.body != [] do %>
            {Helpers.highlight_text(Helpers.truncate_body(@node.body["content"]), @highlights.body)}
          <% else %>
            {Helpers.truncate_body(@node.body["content"])}
          <% end %>
        </div>
      </div>
      <div class="search-result-meta">
        <span :if={@node.priority != nil} class={["search-result-priority", Helpers.priority_class(@node.priority, :css)]}>
          P{@node.priority}
        </span>
      </div>
    </button>
    """
  end
end
