defmodule OpenTrackWeb.PageControllerTest do
  use OpenTrackWeb.ConnCase

  test "the welcome page offers the journal and account registration", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert [_] = document |> LazyHTML.query("#journal-title") |> LazyHTML.to_tree()

    assert [_] =
             document
             |> LazyHTML.query("#landing-journal[href='/app/journal']")
             |> LazyHTML.to_tree()

    assert [_] =
             document
             |> LazyHTML.query("#header-signup[href='/users/register']")
             |> LazyHTML.to_tree()
  end
end
