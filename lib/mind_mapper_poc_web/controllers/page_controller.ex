defmodule MindMapperPocWeb.PageController do
  use MindMapperPocWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
