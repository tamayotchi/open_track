defmodule OpenTrack.Secrets do
  @moduledoc "Resolves the authentication token signing secret from runtime configuration."

  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        OpenTrack.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:open_track, :token_signing_secret)
  end
end
