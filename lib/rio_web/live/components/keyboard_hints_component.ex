defmodule RioWeb.Components.KeyboardHintsComponent do
  @moduledoc """
  Keyboard shortcuts hint panel that can be expanded/collapsed.
  """
  use RioWeb, :html

  attr :hints_expanded, :boolean, required: true

  def keyboard_hints(assigns) do
    ~H"""
    <div class={["mind-map-hints", @hints_expanded && "expanded"]}>
      <%= if @hints_expanded do %>
        <%!-- Expanded view with all hints --%>
        <div class="hints-grid">
          <div class="hints-section">
            <div class="hints-title">Navigation</div>
            <div class="hints-row">
              <span class="kbd kbd-xs">h</span><span class="kbd kbd-xs">j</span><span class="kbd kbd-xs">k</span><span class="kbd kbd-xs">l</span>
              <span class="hints-desc">move focus</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">J</span><span class="kbd kbd-xs">K</span>
              <span class="hints-desc">jump across subtrees</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">f</span>
              <span class="hints-desc">focus subtree</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">H</span>
              <span class="hints-desc">go up one level</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">c</span>
              <span class="hints-desc">center node</span>
            </div>
          </div>
          <div class="hints-section">
            <div class="hints-title">Nodes</div>
            <div class="hints-row">
              <span class="kbd kbd-xs">o</span>
              <span class="hints-desc">add child</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">O</span>
              <span class="hints-desc">add sibling</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">i</span>
              <span class="hints-desc">edit title</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">Space</span>
              <span class="hints-desc">view details</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">⌫</span>
              <span class="hints-desc">delete node</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">z</span>
              <span class="hints-desc">archive node</span>
            </div>
          </div>
          <div class="hints-section">
            <div class="hints-title">Actions</div>
            <div class="hints-row">
              <span class="kbd kbd-xs">t</span>
              <span class="hints-desc">toggle todo</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">p</span>
              <span class="hints-desc">set priority</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">d</span>
              <span class="hints-desc">set due date</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">a</span>
              <span class="hints-desc">attach link</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">g</span>
              <span class="hints-desc">open link</span>
            </div>
          </div>
          <div class="hints-section">
            <div class="hints-title">Modals</div>
            <div class="hints-row">
              <span class="kbd kbd-xs">⌘P</span>
              <span class="hints-desc">search</span>
            </div>
            <div class="hints-row">
              <span class="kbd kbd-xs">T</span>
              <span class="hints-desc">todo list</span>
            </div>
          </div>
        </div>
        <div class="hints-footer">
          <span class="kbd kbd-xs">?</span> to collapse
        </div>
      <% else %>
        <%!-- Compact view --%>
        <span class="kbd kbd-xs">h</span><span class="kbd kbd-xs">j</span><span class="kbd kbd-xs">k</span><span class="kbd kbd-xs">l</span>
        navigate <span class="mx-2">·</span>
        <span class="kbd kbd-xs">o</span>
        child <span class="mx-2">·</span>
        <span class="kbd kbd-xs">Space</span>
        details <span class="mx-2">·</span>
        <span class="kbd kbd-xs">⌫</span>
        delete <span class="mx-2">·</span>
        <span class="kbd kbd-xs">?</span>
        more
      <% end %>
    </div>
    """
  end
end
