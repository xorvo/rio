defmodule RioWeb.Api.InboxJSON do
  alias Rio.Inbox.InboxItem

  def index(%{items: items}) do
    %{data: Enum.map(items, &data/1)}
  end

  def show(%{item: item}) do
    %{data: data(item)}
  end

  def batch(%{results: results}) do
    %{
      data: %{
        created: length(results.ok),
        failed: length(results.error),
        items: Enum.map(results.ok, &data/1),
        errors:
          Enum.map(results.error, fn {index, errors} ->
            %{index: index, errors: errors}
          end)
      }
    }
  end

  defp data(%InboxItem{} = item) do
    %{
      id: item.id,
      title: item.title,
      body: item.body,
      is_todo: item.is_todo,
      priority: item.priority,
      link: item.link,
      due_date: item.due_date,
      edge_label: item.edge_label,
      status: item.status,
      source: item.source,
      expires_at: item.expires_at,
      metadata: item.metadata,
      target_parent_id: item.target_parent_id,
      target_parent_alias: item.target_parent_alias,
      node_id: item.node_id,
      placed_at: item.placed_at,
      inserted_at: item.inserted_at,
      updated_at: item.updated_at
    }
  end
end
