defmodule RioWeb.MindMapLive.InboxHandlers do
  @moduledoc """
  Event handlers for the inbox panel.
  Handles toggling, dismissal, placement, and quick capture.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Rio.Inbox
  alias RioWeb.MindMapLive.Helpers

  def toggle_inbox(socket) do
    new_open = !socket.assigns.inbox_open

    socket =
      if new_open do
        reload_inbox(socket)
      else
        socket
      end

    {:noreply, assign(socket, :inbox_open, new_open)}
  end

  def dismiss_item(socket, %{"id" => id}) do
    item = Inbox.get_item!(id)
    {:ok, _} = Inbox.dismiss_item(item)
    {:noreply, reload_inbox(socket)}
  end

  def extend_item(socket, %{"id" => id}) do
    item = Inbox.get_item!(id)
    {:ok, _} = Inbox.extend_expiration(item, 7)
    {:noreply, reload_inbox(socket)}
  end

  def place_item(socket, %{"item_id" => item_id, "parent_id" => parent_id}) do
    item = Inbox.get_item!(item_id)

    case Inbox.place_item(item, parent_id) do
      {:ok, %{node: _node}} ->
        {:noreply,
         socket
         |> reload_inbox()
         |> Helpers.reload_tree()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to place item: #{inspect(reason)}")}
    end
  end

  def quick_capture(socket, %{"title" => title} = params) do
    title = String.trim(title)

    if title == "" do
      {:noreply, socket}
    else
      attrs = %{
        "title" => title,
        "source" => "manual",
        "is_todo" => params["is_todo"] == "true"
      }

      case Inbox.create_item(attrs) do
        {:ok, _item} ->
          {:noreply, reload_inbox(socket)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to create inbox item")}
      end
    end
  end

  def reload_inbox(socket) do
    items = Inbox.list_pending_items()

    socket
    |> assign(:inbox_items, items)
    |> assign(:inbox_count, length(items))
  end
end
