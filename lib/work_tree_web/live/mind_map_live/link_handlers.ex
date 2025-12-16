defmodule WorkTreeWeb.MindMapLive.LinkHandlers do
  @moduledoc """
  Link-related event handlers for mind map nodes.
  Handles opening, editing, and saving node links.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3]

  alias WorkTree.MindMaps
  alias WorkTreeWeb.MindMapLive.Helpers

  @doc """
  Opens the link edit modal for a node.
  """
  def open_link_modal(socket, %{"id" => id}) do
    node = Enum.find(socket.assigns.nodes, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :link_edit_node, node)}
  end

  @doc """
  Closes the link edit modal.
  """
  def close_link_modal(socket) do
    {:noreply, assign(socket, :link_edit_node, nil)}
  end

  @doc """
  Saves a link to a node.
  Empty string clears the link.
  """
  def save_link(socket, %{"link" => link}) do
    node = socket.assigns.link_edit_node
    link = String.trim(link)

    # Allow empty string to clear the link
    link_value = if link == "", do: nil, else: link

    case MindMaps.update_node(node, %{link: link_value}) do
      {:ok, _updated_node} ->
        {:noreply,
         socket
         |> Helpers.reload_tree()
         |> assign(:link_edit_node, nil)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Invalid URL. Must start with http:// or https://")}
    end
  end

  @doc """
  Handles link validation (currently no-op, HTML5 handles it).
  """
  def validate_link(socket) do
    {:noreply, socket}
  end

  @doc """
  Opens a node's link in a new browser tab.
  """
  def open_node_link(socket, %{"id" => id}) do
    node = Enum.find(socket.assigns.nodes, &(&1.id == String.to_integer(id)))

    if node && node.link do
      {:noreply, push_event(socket, "open-link", %{url: node.link})}
    else
      {:noreply, socket}
    end
  end
end
