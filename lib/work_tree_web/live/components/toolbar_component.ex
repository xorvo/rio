defmodule WorkTreeWeb.Components.ToolbarComponent do
  @moduledoc """
  Toolbar component with home navigation and theme selector.
  """
  use WorkTreeWeb, :html

  attr :ancestors, :list, required: true

  def toolbar(assigns) do
    ~H"""
    <div class="mind-map-toolbar">
      <.link :if={@ancestors != []} navigate={~p"/"} class="btn btn-ghost btn-sm">
        <span class="text-lg">←</span> Home
      </.link>
      <div class="flex-1"></div>
      <.todo_filter_button />
      <.theme_selector />
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

  defp theme_selector(assigns) do
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
            d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01"
          />
        </svg>
        Theme
      </div>
      <div
        tabindex="0"
        class="dropdown-content bg-base-200 rounded-box z-50 p-3 shadow-lg"
      >
        <div class="flex gap-6">
          <%!-- System column --%>
          <div class="flex flex-col gap-1">
            <div class="text-xs font-semibold text-base-content/60 px-2 pb-1">System</div>
            <.theme_button theme="system" label="Auto" />
          </div>
          <%!-- Light themes column --%>
          <div class="flex flex-col gap-1">
            <div class="text-xs font-semibold text-base-content/60 px-2 pb-1">Light</div>
            <.theme_button theme="light" label="Light" />
            <.theme_button theme="cupcake" label="Cupcake" />
            <.theme_button theme="bumblebee" label="Bumblebee" />
            <.theme_button theme="emerald" label="Emerald" />
            <.theme_button theme="corporate" label="Corporate" />
            <.theme_button theme="retro" label="Retro" />
            <.theme_button theme="garden" label="Garden" />
            <.theme_button theme="lofi" label="Lofi" />
            <.theme_button theme="pastel" label="Pastel" />
          </div>
          <%!-- More light themes column --%>
          <div class="flex flex-col gap-1">
            <div class="text-xs font-semibold text-base-content/60 px-2 pb-1">&nbsp;</div>
            <.theme_button theme="fantasy" label="Fantasy" />
            <.theme_button theme="wireframe" label="Wireframe" />
            <.theme_button theme="cmyk" label="CMYK" />
            <.theme_button theme="autumn" label="Autumn" />
            <.theme_button theme="acid" label="Acid" />
            <.theme_button theme="lemonade" label="Lemonade" />
            <.theme_button theme="winter" label="Winter" />
            <.theme_button theme="nord" label="Nord" />
          </div>
          <%!-- Dark themes column --%>
          <div class="flex flex-col gap-1">
            <div class="text-xs font-semibold text-base-content/60 px-2 pb-1">Dark</div>
            <.theme_button theme="dark" label="Dark" />
            <.theme_button theme="synthwave" label="Synthwave" />
            <.theme_button theme="cyberpunk" label="Cyberpunk" />
            <.theme_button theme="valentine" label="Valentine" />
            <.theme_button theme="halloween" label="Halloween" />
            <.theme_button theme="forest" label="Forest" />
            <.theme_button theme="aqua" label="Aqua" />
            <.theme_button theme="black" label="Black" />
          </div>
          <%!-- More dark themes column --%>
          <div class="flex flex-col gap-1">
            <div class="text-xs font-semibold text-base-content/60 px-2 pb-1">&nbsp;</div>
            <.theme_button theme="luxury" label="Luxury" />
            <.theme_button theme="dracula" label="Dracula" />
            <.theme_button theme="business" label="Business" />
            <.theme_button theme="night" label="Night" />
            <.theme_button theme="coffee" label="Coffee" />
            <.theme_button theme="dim" label="Dim" />
            <.theme_button theme="sunset" label="Sunset" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :theme, :string, required: true
  attr :label, :string, required: true

  defp theme_button(assigns) do
    ~H"""
    <button
      data-phx-theme={@theme}
      phx-click={JS.dispatch("phx:set-theme")}
      class="btn btn-ghost btn-sm justify-start"
    >
      {@label}
    </button>
    """
  end
end
