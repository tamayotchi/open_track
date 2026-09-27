defmodule OpenTrack.Repo do
  use AshSqlite.Repo, otp_app: :open_track

  @impl true
  def write_transactions?, do: true
end
