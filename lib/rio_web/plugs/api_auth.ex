defmodule RioWeb.Plugs.ApiAuth do
  @moduledoc """
  Simple bearer token authentication for the API.
  If no API key is configured (RIO_API_KEY not set), the API is open.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    api_key = Application.get_env(:rio, :api_key)

    cond do
      is_nil(api_key) or api_key == "" ->
        conn

      get_bearer_token(conn) == api_key ->
        conn

      true ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Invalid or missing API key"})
        |> halt()
    end
  end

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> key] -> key
      _ -> nil
    end
  end
end
