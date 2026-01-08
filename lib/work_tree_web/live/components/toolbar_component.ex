defmodule WorkTreeWeb.Components.ToolbarComponent do
  @moduledoc """
  Toolbar component with home navigation and settings menu.
  """
  use WorkTreeWeb, :html

  attr :ancestors, :list, required: true
  attr :show_archived, :boolean, default: false

  def toolbar(assigns) do
    ~H"""
    <div class="mind-map-toolbar">
      <.link :if={@ancestors != []} navigate={~p"/"} class="btn btn-ghost btn-sm">
        <span class="text-lg">←</span> Home
      </.link>
      <div class="flex-1"></div>
      <.todo_filter_button />
      <.settings_menu show_archived={@show_archived} />
    </div>
    """
  end

  defp todo_filter_button(assigns) do
    ~H"""
    <button
      type="button"
      class="btn btn-ghost btn-sm gap-1"
      phx-click="open_todo_filter"
      title="Todo list (v)"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-4 w-4"
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
      Todos
    </button>
    """
  end

  attr :show_archived, :boolean, required: true

  defp settings_menu(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm gap-1">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-4 w-4"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
          />
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
          />
        </svg>
        Settings
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-200 rounded-box z-50 w-52 p-2 shadow-lg"
      >
        <%!-- Show Archived Toggle --%>
        <li>
          <label class="flex items-center gap-2 cursor-pointer">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-4 w-4 opacity-60"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"
              />
            </svg>
            Show Archived
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary ml-auto"
              checked={@show_archived}
              phx-click="toggle_show_archived"
            />
          </label>
        </li>

        <div class="divider my-1"></div>

        <%!-- Theme Picker Button --%>
        <li>
          <button type="button" phx-click="open_theme_picker" class="flex items-center gap-2">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-4 w-4 opacity-60"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01"
              />
            </svg>
            Theme
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
