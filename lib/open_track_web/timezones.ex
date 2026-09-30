defmodule OpenTrackWeb.Timezones do
  @moduledoc "Timezone choices, display formatting, and local calendar boundaries for the web UI."

  @utc "Etc/UTC"

  def utc, do: @utc

  def timezone_options do
    zones =
      Tzdata.zone_list()
      |> Enum.reject(&(&1 == @utc))
      |> Enum.sort()
      |> Enum.map(&{label(&1), &1})

    [{"UTC — Coordinated Universal Time", @utc} | zones]
  end

  def label(@utc), do: "UTC"
  def label(zone), do: String.replace(zone, "_", " ")

  def local_datetime(timestamp, zone), do: DateTime.shift_zone!(timestamp, zone)
  def local_date(timestamp, zone), do: timestamp |> local_datetime(zone) |> DateTime.to_date()
  def today(zone, now \\ DateTime.utc_now()), do: local_date(now, zone)

  @doc "UTC instants bounding an inclusive range of local dates; the end instant is exclusive."
  def utc_range(first_date, last_date, zone) do
    {midnight_utc(first_date, zone), midnight_utc(Date.add(last_date, 1), zone)}
  end

  defp midnight_utc(date, zone) do
    # Some regions change clocks at midnight. Choose the first occurrence on
    # overlaps, or the first valid instant after a gap (including skipped dates).
    local =
      case DateTime.new(date, ~T[00:00:00], zone) do
        {:ok, datetime} -> datetime
        {:ambiguous, first, _second} -> first
        {:gap, _before, after_gap} -> after_gap
      end

    DateTime.shift_zone!(local, @utc)
  end
end
