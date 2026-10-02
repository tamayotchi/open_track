defmodule OpenTrackWeb.PageControllerTest do
  use OpenTrackWeb.ConnCase

  import OpenTrack.Fixtures

  test "old account and journal links redirect to the signed-in user's profile", %{conn: conn} do
    owner = user()

    for path <- ["/app/account", "/app/journal"] do
      assert conn |> get(path) |> redirected_to() == "/users/log-in"

      assert conn |> log_in(owner) |> get(path) |> redirected_to() ==
               "/app/profile/#{owner.nickname}"
    end
  end

  test "the welcome page offers account registration", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert [_] = document |> LazyHTML.query("#journal-title") |> LazyHTML.to_tree()

    assert [_] =
             document
             |> LazyHTML.query("#landing-profile[href='/users/register']")
             |> LazyHTML.to_tree()

    assert [_] =
             document
             |> LazyHTML.query("#header-signup[href='/users/register']")
             |> LazyHTML.to_tree()
  end
end
