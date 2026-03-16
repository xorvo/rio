defmodule RioWeb.PageController do
  use RioWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
