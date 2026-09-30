defmodule OpenTrackWeb.TimezonePreferencesLiveTest do
  use OpenTrackWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpenTrack.Fixtures

  alias OpenTrack.Accounts

  setup %{conn: conn} do
    owner = user()
    %{conn: log_in(conn, owner), owner: owner}
  end

  test "timezone defaults to UTC and a selected timezone persists without country fields", %{
    conn: conn,
    owner: owner
  } do
    {:ok, view, _} = live(conn, "/app/account")
    assert has_element?(view, "#timezone-form select[name='preferences[timezone]']")
    assert has_element?(view, "#preferences_timezone option[value='Etc/UTC'][selected]")
    assert has_element?(view, "#preferences_timezone option[value='America/Bogota']")
    refute has_element?(view, "#country-preferences")
    refute has_element?(view, "[name='preferences[country_code]']")

    view |> form("#timezone-form", preferences: %{timezone: "America/Bogota"}) |> render_change()
    view |> form("#timezone-form", preferences: %{timezone: "America/Bogota"}) |> render_submit()
    assert has_element?(view, "#flash-info", "Timezone preferences saved.")
    assert Accounts.get_settings_for_user!(owner.id, actor: owner).timezone == "America/Bogota"

    {:ok, reloaded, _} = live(conn, "/app/account")

    assert has_element?(
             reloaded,
             "#preferences_timezone option[value='America/Bogota'][selected]"
           )

    # Saving targets after timezone preferences updates the same record.
    reloaded |> form("#targets-form", targets: %{target_weight_kg: "70"}) |> render_submit()
    settings = Accounts.get_settings_for_user!(owner.id, actor: owner)
    assert settings.target_weight_kg == 70.0
    assert settings.timezone == "America/Bogota"
  end

  test "timezone updates preserve existing targets and can return to UTC", %{
    conn: conn,
    owner: owner
  } do
    {:ok, view, _} = live(conn, "/app/account")
    view |> form("#targets-form", targets: %{target_weight_kg: "72"}) |> render_submit()

    view
    |> form("#timezone-form", preferences: %{timezone: "America/Los_Angeles"})
    |> render_submit()

    refute has_element?(view, "#timezone-form [role='alert']")

    settings = Accounts.get_settings_for_user!(owner.id, actor: owner)
    assert settings.timezone == "America/Los_Angeles"
    assert settings.target_weight_kg == 72.0

    {:ok, reloaded, _} = live(conn, "/app/account")

    assert has_element?(
             reloaded,
             "#preferences_timezone option[value='America/Los_Angeles'][selected]"
           )

    reloaded |> form("#timezone-form", preferences: %{timezone: "Etc/UTC"}) |> render_submit()
    settings = Accounts.get_settings_for_user!(owner.id, actor: owner)
    assert settings.timezone == "Etc/UTC"
    assert settings.target_weight_kg == 72.0
  end

  test "blank or nil timezones cannot clear the stored preference", %{
    conn: conn,
    owner: owner
  } do
    Accounts.create_settings!(%{timezone: "America/Bogota"}, actor: owner)
    {:ok, view, _} = live(conn, "/app/account")

    for zone <- ["", nil] do
      render_change(view, "validate-timezone", %{"preferences" => %{"timezone" => zone}})
      assert has_element?(view, "#timezone-form [role='alert']")
      render_submit(view, "save-timezone", %{"preferences" => %{"timezone" => zone}})
      assert has_element?(view, "#timezone-form [role='alert']")
      assert Accounts.get_settings_for_user!(owner.id, actor: owner).timezone == "America/Bogota"
    end
  end
end
