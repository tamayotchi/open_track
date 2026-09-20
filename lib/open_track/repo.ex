defmodule OpenTrack.Repo do
  use Ecto.Repo,
    otp_app: :open_track,
    adapter: Ecto.Adapters.SQLite3
end
