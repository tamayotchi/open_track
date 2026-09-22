import Config
config :open_track, token_signing_secret: "iqs8owz38g37IVNr/sxQ6rojZJG/CT+X"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true]

# This stores only file bytes in memory; it is not an Ash persistence data layer.
config :open_track, OpenTrack.Food.FoodPhoto, storage: [service: {AshStorage.Service.Test, []}]
config :open_track, OpenTrack.Accounts.User, storage: [service: {AshStorage.Service.Test, []}]

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :open_track, OpenTrack.Repo,
  database: Path.expand("../open_track_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :open_track, OpenTrackWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "/ADRSlS0lTQiFw7+JJdkjRJw0gxsXvVN8X3gF9g9xODwxJERU3y+zebI061xnDnv",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
