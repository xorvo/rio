defmodule WorkTreeWeb.MindMapLive.NodeFormComponent do
  use WorkTreeWeb, :live_component

  alias WorkTree.MindMaps

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h3 class="text-lg font-semibold mb-4"><%= @title %></h3>

      <.form
        for={@form}
        id="node-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4">
          <div>
            <label class="label">
              <span class="label-text">Title</span>
            </label>
            <input
              type="text"
              name={@form[:title].name}
              value={@form[:title].value}
              class={["input input-bordered w-full", @form[:title].errors != [] && "input-error"]}
              placeholder="Enter title..."
              phx-debounce="300"
            />
            <p :for={{msg, _opts} <- @form[:title].errors} class="text-error text-sm mt-1">
              <%= msg %>
            </p>
          </div>

          <div>
            <label class="label">
              <span class="label-text">Body (optional)</span>
            </label>
            <textarea
              name="body_content"
              class="textarea textarea-bordered w-full h-24"
              placeholder="Add details..."
              phx-debounce="300"
            ><%= get_body_content(@form) %></textarea>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="checkbox"
                name={@form[:is_todo].name}
                checked={@form[:is_todo].value}
                class="checkbox checkbox-primary"
              />
              <span class="label-text">Mark as TODO item</span>
            </label>
          </div>

          <div :if={@action != :new_root} class="form-control">
            <label class="label">
              <span class="label-text">Edge Label (optional)</span>
            </label>
            <input
              type="text"
              name={@form[:edge_label].name}
              value={@form[:edge_label].value}
              class="input input-bordered w-full input-sm"
              placeholder="Label on connecting line..."
            />
          </div>
        </div>

        <div class="modal-action">
          <button type="button" class="btn btn-ghost" phx-click={JS.exec("data-cancel", to: "#node-form")}>
            Cancel
          </button>
          <button type="submit" class="btn btn-primary" phx-disable-with="Saving...">
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
     |> assign_form(changeset)}
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
