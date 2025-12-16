defmodule WorkTreeWeb.Components.LinkInputComponent do
  @moduledoc """
  Quick inline input for adding/editing links on nodes.
  Similar to priority picker but with a text input.
  """
  use WorkTreeWeb, :html

  attr :link_input_open, :boolean, required: true
  attr :link_input_node, :map, required: true

  def link_input(assigns) do
    ~H"""
    <div
      :if={@link_input_open && @link_input_node}
      id="link-input-backdrop"
      class="link-input-backdrop"
      phx-click="close_link_input"
      phx-window-keydown="link_input_keydown"
    >
      <div
        id="link-input-modal"
        class="link-input-modal"
        onclick="event.stopPropagation()"
      >
        <form phx-submit="save_link_input" class="link-input-form">
          <input
            type="text"
            name="link"
            value={@link_input_node.link || ""}
            placeholder="Paste URL here..."
            class="link-input-field"
            phx-hook="FocusEnd"
            id="link-input-field"
          />
        </form>

        <div class="link-input-footer">
          <span><span class="kbd kbd-xs">↵</span> save</span>
          <span><span class="kbd kbd-xs">Esc</span> cancel</span>
          <%= if @link_input_node.link do %>
            <span class="text-base-content/40">clear input to remove</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
