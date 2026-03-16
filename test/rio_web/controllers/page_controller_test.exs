defmodule RioWeb.PageControllerTest do
  use RioWeb.ConnCase

  test "GET / renders mind map", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "mind-map-container"
  end
end
