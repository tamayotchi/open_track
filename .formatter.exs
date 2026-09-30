[
  import_deps: [
    :ash_oban,
    :oban,
    :ash_ai,
    :ash_phoenix,
    :ash_sqlite,
    :ash_authentication,
    :ash_storage,
    :ash,
    :reactor,
    :ecto,
    :ecto_sql,
    :phoenix
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
