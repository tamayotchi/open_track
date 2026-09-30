defmodule OpenTrackWeb.TimezonesTest do
  use ExUnit.Case, async: true

  alias OpenTrackWeb.Timezones

  test "timezone choices come from IANA, with UTC first and distinct regional options" do
    options = Timezones.timezone_options()
    assert hd(options) == {"UTC — Coordinated Universal Time", "Etc/UTC"}
    assert {"America/Bogota", "America/Bogota"} in options
    assert {"America/New York", "America/New_York"} in options
    assert {"America/Los Angeles", "America/Los_Angeles"} in options
    assert {"Asia/Tokyo", "Asia/Tokyo"} in options
    assert length(options) == length(Enum.uniq_by(options, &elem(&1, 1)))

    for {_label, zone} <- options, do: assert(Tzdata.zone_exists?(zone))
  end

  test "today and upload dates follow the local calendar, not the UTC date" do
    timestamp = ~U[2026-01-06 02:00:00Z]
    assert Timezones.today("Etc/UTC", timestamp) == ~D[2026-01-06]
    assert Timezones.today("America/Bogota", timestamp) == ~D[2026-01-05]
    assert Timezones.local_date(timestamp, "America/Bogota") == ~D[2026-01-05]
    assert Timezones.local_datetime(timestamp, "America/Bogota").hour == 21
    assert Timezones.today("Pacific/Auckland", ~U[2026-01-06 23:00:00Z]) == ~D[2026-01-07]
  end

  test "Colombia date ranges start and end at local midnight, converted to UTC" do
    assert Timezones.utc_range(~D[2026-01-05], ~D[2026-01-06], "America/Bogota") ==
             {~U[2026-01-05 05:00:00Z], ~U[2026-01-07 05:00:00Z]}

    assert Timezones.utc_range(~D[2026-01-05], ~D[2026-01-05], "Etc/UTC") ==
             {~U[2026-01-05 00:00:00Z], ~U[2026-01-06 00:00:00Z]}
  end

  test "daylight saving days have 23 or 25 hours instead of a fixed 24" do
    {from, until} = Timezones.utc_range(~D[2026-03-08], ~D[2026-03-08], "America/New_York")
    assert from == ~U[2026-03-08 05:00:00Z]
    assert until == ~U[2026-03-09 04:00:00Z]
    assert DateTime.diff(until, from, :hour) == 23

    {from, until} = Timezones.utc_range(~D[2026-11-01], ~D[2026-11-01], "America/New_York")
    assert from == ~U[2026-11-01 04:00:00Z]
    assert until == ~U[2026-11-02 05:00:00Z]
    assert DateTime.diff(until, from, :hour) == 25
  end

  test "midnight clock changes and skipped dates do not crash or drop the first hour" do
    assert Timezones.utc_range(~D[2024-09-08], ~D[2024-09-08], "America/Santiago") ==
             {~U[2024-09-08 04:00:00Z], ~U[2024-09-09 03:00:00Z]}

    assert Timezones.utc_range(~D[2024-11-03], ~D[2024-11-03], "America/Havana") ==
             {~U[2024-11-03 04:00:00Z], ~U[2024-11-04 05:00:00Z]}

    assert Timezones.utc_range(~D[2011-12-30], ~D[2011-12-30], "Pacific/Apia") ==
             {~U[2011-12-30 10:00:00Z], ~U[2011-12-30 10:00:00Z]}
  end
end
