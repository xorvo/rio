defmodule WorkTreeWeb.Components.ThemePickerComponent do
  @moduledoc """
  Theme picker modal component for selecting app themes.
  Displays a grid of all available DaisyUI themes organized by light/dark.
  """
  use WorkTreeWeb, :html

  @light_themes [
    {"light", "Light"},
    {"cupcake", "Cupcake"},
    {"bumblebee", "Bumblebee"},
    {"emerald", "Emerald"},
    {"corporate", "Corporate"},
    {"retro", "Retro"},
    {"garden", "Garden"},
    {"lofi", "Lofi"},
    {"pastel", "Pastel"},
    {"fantasy", "Fantasy"},
    {"wireframe", "Wireframe"},
    {"cmyk", "CMYK"},
    {"autumn", "Autumn"},
    {"acid", "Acid"},
    {"lemonade", "Lemonade"},
    {"winter", "Winter"},
    {"nord", "Nord"}
  ]

  @dark_themes [
    {"dark", "Dark"},
    {"synthwave", "Synthwave"},
    {"cyberpunk", "Cyberpunk"},
    {"valentine", "Valentine"},
    {"halloween", "Halloween"},
    {"forest", "Forest"},
    {"aqua", "Aqua"},
    {"black", "Black"},
    {"luxury", "Luxury"},
    {"dracula", "Dracula"},
    {"business", "Business"},
    {"night", "Night"},
    {"coffee", "Coffee"},
    {"dim", "Dim"},
    {"sunset", "Sunset"}
  ]

  attr :theme_picker_open, :boolean, default: false

  def theme_picker(assigns) do
    assigns =
      assigns
      |> assign(:light_themes, @light_themes)
      |> assign(:dark_themes, @dark_themes)

    ~H"""
    <div
      :if={@theme_picker_open}
      id="theme-picker-modal"
      class="theme-picker-backdrop"
      phx-click="close_theme_picker"
      phx-window-keydown="theme_picker_keydown"
    >
      <div class="theme-picker" phx-click-away="close_theme_picker">
        <div class="theme-picker-header">
          <h3 class="theme-picker-title">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01" />
            </svg>
            Choose Theme
          </h3>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-circle"
            phx-click="close_theme_picker"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div class="theme-picker-content">
          <div class="theme-section">
            <div class="theme-section-header">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
              </svg>
              Light Themes
            </div>
            <div class="theme-grid">
              <%= for {theme, label} <- @light_themes do %>
                <.theme_button theme={theme} label={label} />
              <% end %>
            </div>
          </div>

          <div class="theme-section">
            <div class="theme-section-header">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" />
              </svg>
              Dark Themes
            </div>
            <div class="theme-grid">
              <%= for {theme, label} <- @dark_themes do %>
                <.theme_button theme={theme} label={label} />
              <% end %>
            </div>
          </div>

          <div class="theme-section-system">
            <button
              type="button"
              data-phx-theme="system"
              phx-click={JS.dispatch("phx:set-theme")}
              class="theme-system-btn"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
              </svg>
              System (Auto)
            </button>
          </div>
        </div>

        <div class="theme-picker-footer">
          <span>Press <kbd class="kbd kbd-xs">Esc</kbd> to close</span>
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
      type="button"
      data-phx-theme={@theme}
      phx-click={JS.dispatch("phx:set-theme")}
      class="theme-btn"
      data-theme={@theme}
    >
      <div class="theme-preview">
        <div class="theme-preview-primary"></div>
        <div class="theme-preview-secondary"></div>
        <div class="theme-preview-accent"></div>
      </div>
      <span class="theme-label">{@label}</span>
    </button>
    """
  end
end
