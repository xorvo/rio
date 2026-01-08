defmodule WorkTreeWeb.MindMapLive.NodeFormComponent do
  use WorkTreeWeb, :live_component

  alias WorkTree.MindMaps

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-5">
      <div class="pb-3 border-b border-base-300">
        <h3 class="text-lg font-semibold text-base-content leading-tight">
          {@form[:title].value || "New Node"}
        </h3>
      </div>

      <.form
        for={@form}
        id="node-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <div>
          <div class="border border-base-300 rounded-lg overflow-hidden">
            <div class="flex gap-0 bg-base-200 border-b border-base-300">
              <button
                type="button"
                class={[
                  "px-3 py-1.5 text-xs font-medium transition-colors",
                  if(!@preview_mode,
                    do: "bg-base-100 text-base-content border-r border-base-300",
                    else: "text-base-content/60 hover:text-base-content hover:bg-base-100/50"
                  )
                ]}
                phx-click="toggle_preview"
                phx-target={@myself}
                phx-value-mode="write"
              >
                Write
              </button>
              <button
                type="button"
                class={[
                  "px-3 py-1.5 text-xs font-medium transition-colors",
                  if(@preview_mode,
                    do: "bg-base-100 text-base-content border-r border-base-300",
                    else: "text-base-content/60 hover:text-base-content hover:bg-base-100/50"
                  )
                ]}
                phx-click="toggle_preview"
                phx-target={@myself}
                phx-value-mode="preview"
              >
                Preview
              </button>
            </div>
            <div class={@preview_mode && "hidden"}>
              <textarea
                id="node-body"
                name="body_content"
                class="w-full h-72 text-sm p-3 bg-base-100 resize-none focus:outline-none"
                placeholder="Add details..."
                phx-debounce="300"
              ><%= get_body_content(@form) %></textarea>
            </div>
            <div
              :if={@preview_mode}
              class="prose prose-sm max-w-none min-h-72 p-3 bg-base-100 text-sm"
            >
              <%= if get_body_content(@form) == "" do %>
                <p class="text-base-content/50 italic">Nothing to preview</p>
              <% else %>
                {WorkTreeWeb.Helpers.Markdown.render(get_body_content(@form))}
              <% end %>
            </div>
          </div>
        </div>

        <details class="group">
          <summary class="flex items-center gap-1 text-xs text-base-content/60 cursor-pointer hover:text-base-content transition-colors select-none">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-3 w-3 transition-transform group-open:rotate-90"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
            </svg>
            Advanced settings
          </summary>
          <div class="mt-3 space-y-3 pl-4">
            <div class="flex items-center gap-2">
              <input
                type="checkbox"
                id="node-is-todo"
                name={@form[:is_todo].name}
                checked={@form[:is_todo].value}
                class="checkbox checkbox-primary checkbox-xs"
              />
              <label for="node-is-todo" class="text-xs text-base-content cursor-pointer">
                Mark as TODO item
              </label>
            </div>

            <div :if={@action != :new_root}>
              <label for="node-edge-label" class="block text-xs text-base-content/80 mb-1">
                Edge Label
              </label>
              <input
                type="text"
                id="node-edge-label"
                name={@form[:edge_label].name}
                value={@form[:edge_label].value}
                class="input input-bordered w-full input-xs"
                placeholder="Label on connecting line..."
              />
            </div>
          </div>
        </details>

        <div class="flex gap-3 justify-end pt-2 border-t border-base-300">
          <button type="submit" class="btn btn-primary btn-sm" phx-disable-with="Saving...">
            Save
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp get_body_content(form) do
    body = form[:body].value || %{}
    body["content"] || ""
  end

  @impl true
  def update(%{node: node} = assigns, socket) do
    changeset = MindMaps.change_node(node)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:preview_mode, fn -> false end)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("toggle_preview", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :preview_mode, mode == "preview")}
  end

  @impl true
  def handle_event("validate", %{"node" => node_params} = params, socket) do
    node_params = process_body_content(node_params, params)

    changeset =
      socket.assigns.node
      |> MindMaps.change_node(node_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"node" => node_params} = params, socket) do
    node_params = process_body_content(node_params, params)
    save_node(socket, socket.assigns.action, node_params)
  end

  defp process_body_content(node_params, params) do
    body_content = params["body_content"] || ""

    body =
      if body_content == "" do
        %{}
      else
        %{"type" => "text", "content" => body_content}
      end

    node_params
    |> Map.put("body", body)
    |> convert_checkbox("is_todo")
  end

  defp convert_checkbox(params, field) do
    case Map.get(params, field) do
      "on" -> Map.put(params, field, true)
      "true" -> Map.put(params, field, true)
      _ -> Map.put(params, field, false)
    end
  end

  defp save_node(socket, :new_root, node_params) do
    case MindMaps.create_root_node(node_params) do
      {:ok, node} ->
        notify_parent({:saved, node})

        {:noreply,
         socket
         |> put_flash(:info, "Mind map created")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_node(socket, :new_child, node_params) do
    case MindMaps.create_child_node(socket.assigns.parent_id, node_params) do
      {:ok, node} ->
        notify_parent({:saved, node})

        {:noreply,
         socket
         |> put_flash(:info, "Node created")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_node(socket, :edit, node_params) do
    case MindMaps.update_node(socket.assigns.node, node_params) do
      {:ok, node} ->
        notify_parent({:saved, node})

        {:noreply,
         socket
         |> put_flash(:info, "Node updated")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "node"))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
