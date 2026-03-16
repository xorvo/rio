defmodule RioWeb.Components.LinkEditModalComponent do
  @moduledoc """
  Modal component for editing node links.
  """
  use RioWeb, :html

  attr :link_edit_node, :map, required: true

  def link_edit_modal(assigns) do
    ~H"""
    <.modal :if={@link_edit_node} id="link-modal" show on_cancel={JS.push("close_link_modal")}>
      <div class="space-y-5">
        <div>
          <h3 class="text-base font-semibold text-base-content">
            {if @link_edit_node.link, do: "Edit Link", else: "Add Link"}
          </h3>
          <p class="mt-1 text-xs text-base-content/60">
            Attach a URL to "{@link_edit_node.title}"
          </p>
        </div>

        <form phx-submit="save_link" phx-change="validate_link" class="space-y-6">
          <div>
            <label for="link-input" class="block text-sm font-medium text-base-content mb-2">
              URL
            </label>
            <input
              type="url"
              name="link"
              value={@link_edit_node.link || ""}
              placeholder="https://example.com"
              class="input input-bordered w-full"
              phx-hook="FocusEnd"
              id="link-input"
              pattern="https?://.*"
              title="URL must start with http:// or https://"
            />
            <p class="mt-2 text-xs text-base-content/50">
              Leave empty to remove the link
            </p>
          </div>

          <div class="flex gap-3 justify-end pt-2">
            <button type="button" phx-click="close_link_modal" class="btn btn-ghost">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary">
              Save Link
            </button>
          </div>
        </form>
      </div>
    </.modal>
    """
  end
end
