defmodule AppName.Repo do
  use Ecto.Repo,
    otp_app: :app_name,
    adapter: Ecto.Adapters.SQLite3
end
