defmodule RioWeb.Api.InboxController do
  use RioWeb, :controller

  alias Rio.Inbox

  action_fallback RioWeb.ApiFallbackController

  def create(conn, params) do
    case Inbox.ingest(params) do
      {:ok, item} ->
        conn
        |> put_status(:created)
        |> render(:show, item: item)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  def batch_create(conn, %{"items" => items}) when is_list(items) do
    results =
      items
      |> Enum.with_index()
      |> Enum.reduce(%{ok: [], error: []}, fn {attrs, index}, acc ->
        case Inbox.ingest(attrs) do
          {:ok, item} ->
            %{acc | ok: [item | acc.ok]}

          {:error, %Ecto.Changeset{} = changeset} ->
            errors = format_changeset_errors(changeset)
            %{acc | error: [{index, errors} | acc.error]}
        end
      end)

    results = %{ok: Enum.reverse(results.ok), error: Enum.reverse(results.error)}

    conn
    |> put_status(:created)
    |> render(:batch, results: results)
  end

  def batch_create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Expected an 'items' array"})
  end

  def index(conn, params) do
    limit = parse_int(params["limit"], 50)
    items = Inbox.list_pending_items(limit: limit)

    render(conn, :index, items: items)
  end

  def update(conn, %{"id" => id} = params) do
    item = Inbox.get_item!(id)

    result =
      cond do
        params["action"] == "dismiss" ->
          Inbox.dismiss_item(item)

        params["action"] == "extend" ->
          days = parse_int(params["days"], 7)
          Inbox.extend_expiration(item, days)

        params["action"] == "place" && params["parent_id"] ->
          Inbox.place_item(item, params["parent_id"])

        true ->
          item
          |> Rio.Inbox.InboxItem.changeset(params)
          |> Rio.Repo.update()
      end

    case result do
      {:ok, updated} ->
        # place_item returns %{item: _, node: _}, others return the item directly
        item = if is_map(updated) && Map.has_key?(updated, :item), do: updated.item, else: updated
        render(conn, :show, item: item)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
