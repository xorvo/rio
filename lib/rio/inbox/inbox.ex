defmodule Rio.Inbox do
  @moduledoc """
  Context module for the inbox feature.
  Manages ingestion, review, and placement of items into the mind map tree.
  """

  import Ecto.Query
  alias Rio.Repo
  alias Rio.Inbox.InboxItem
  alias Rio.MindMaps
  alias Rio.MindMaps.Node

  @default_expiry_days 7

  # CRUD

  def create_item(attrs) do
    attrs = set_default_expiration(attrs)

    result =
      %InboxItem{}
      |> InboxItem.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, item} ->
        broadcast_update()
        {:ok, item}

      error ->
        error
    end
  end

  def get_item!(id), do: Repo.get!(InboxItem, id)
  def get_item(id), do: Repo.get(InboxItem, id)

  def list_pending_items(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    now = DateTime.utc_now()

    from(i in InboxItem,
      where: i.status == "pending",
      where: is_nil(i.expires_at) or i.expires_at > ^now,
      order_by: [asc: fragment("coalesce(?, 999)", i.priority), asc: i.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def list_items(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status)

    query = from(i in InboxItem, order_by: [desc: i.inserted_at], limit: ^limit)

    query =
      if status do
        where(query, [i], i.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  def pending_count do
    now = DateTime.utc_now()

    from(i in InboxItem,
      where: i.status == "pending",
      where: is_nil(i.expires_at) or i.expires_at > ^now
    )
    |> Repo.aggregate(:count)
  end

  def dismiss_item(%InboxItem{} = item) do
    result =
      item
      |> InboxItem.changeset(%{status: "dismissed"})
      |> Repo.update()

    case result do
      {:ok, item} ->
        broadcast_update()
        {:ok, item}

      error ->
        error
    end
  end

  def extend_expiration(%InboxItem{} = item, days \\ @default_expiry_days) do
    base = item.expires_at || DateTime.utc_now()
    new_expires = DateTime.add(base, days * 86_400, :second)

    result =
      item
      |> InboxItem.changeset(%{expires_at: new_expires})
      |> Repo.update()

    case result do
      {:ok, item} ->
        broadcast_update()
        {:ok, item}

      error ->
        error
    end
  end

  # Placement

  def place_item(%InboxItem{} = item, parent_id) when is_binary(parent_id) do
    node_attrs = item_to_node_attrs(item)

    Repo.transaction(fn ->
      case MindMaps.create_child_node(parent_id, node_attrs) do
        {:ok, node} ->
          {:ok, updated_item} =
            item
            |> InboxItem.changeset(%{
              status: "placed",
              node_id: node.id,
              placed_at: DateTime.utc_now()
            })
            |> Repo.update()

          broadcast_update()
          %{item: updated_item, node: node}

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  # Ingestion (from API)

  def ingest(attrs) do
    attrs = stringify_keys(attrs)
    attrs = Map.put_new(attrs, "source", "api")

    case resolve_parent(attrs) do
      {:ok, parent_id} ->
        # Auto-place: parent resolved successfully
        auto_place(attrs, parent_id)

      :no_parent ->
        # Queue as pending
        create_item(attrs)
    end
  end

  # Expiration

  def expire_stale_items do
    now = DateTime.utc_now()

    {count, _} =
      from(i in InboxItem,
        where: i.status == "pending",
        where: not is_nil(i.expires_at),
        where: i.expires_at <= ^now
      )
      |> Repo.update_all(set: [status: "expired"])

    if count > 0, do: broadcast_update()

    {:ok, count}
  end

  # Private

  defp auto_place(attrs, parent_id) do
    node_attrs = %{
      "title" => attrs["title"],
      "body" => attrs["body"] || %{},
      "is_todo" => attrs["is_todo"] || false,
      "priority" => attrs["priority"],
      "link" => attrs["link"],
      "due_date" => attrs["due_date"],
      "edge_label" => attrs["edge_label"]
    }

    Repo.transaction(fn ->
      case MindMaps.create_child_node(parent_id, node_attrs) do
        {:ok, node} ->
          attrs_with_placement =
            Map.merge(attrs, %{
              "status" => "auto_placed",
              "node_id" => node.id,
              "placed_at" => DateTime.utc_now()
            })

          {:ok, item} =
            %InboxItem{}
            |> InboxItem.changeset(set_default_expiration(attrs_with_placement))
            |> Repo.insert()

          broadcast_update()
          item

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp resolve_parent(attrs) do
    cond do
      # Direct parent ID provided
      parent_id = attrs["target_parent_id"] ->
        case MindMaps.get_node(parent_id) do
          nil -> :no_parent
          _node -> {:ok, parent_id}
        end

      # Alias-based lookup
      parent_alias = attrs["target_parent_alias"] ->
        case Repo.one(from(n in Node, where: n.alias == ^parent_alias and is_nil(n.deleted_at))) do
          nil -> :no_parent
          node -> {:ok, node.id}
        end

      true ->
        :no_parent
    end
  end

  defp item_to_node_attrs(%InboxItem{} = item) do
    %{
      "title" => item.title,
      "body" => item.body || %{},
      "is_todo" => item.is_todo || false,
      "priority" => item.priority,
      "link" => item.link,
      "due_date" => item.due_date,
      "edge_label" => item.edge_label
    }
  end

  defp set_default_expiration(attrs) do
    attrs = stringify_keys(attrs)

    cond do
      Map.has_key?(attrs, "expires_at") ->
        attrs

      expires_in = attrs["expires_in_days"] ->
        days = if is_binary(expires_in), do: String.to_integer(expires_in), else: expires_in
        expires_at = DateTime.utc_now() |> DateTime.add(days * 86_400, :second)
        Map.put(attrs, "expires_at", expires_at)

      true ->
        expires_at = DateTime.utc_now() |> DateTime.add(@default_expiry_days * 86_400, :second)
        Map.put(attrs, "expires_at", expires_at)
    end
  end

  defp broadcast_update do
    Phoenix.PubSub.broadcast(Rio.PubSub, "inbox", {:inbox_updated, %{}})
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
