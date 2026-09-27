defmodule OpenTrack.UnavailableStorage do
  @moduledoc false
  @behaviour AshStorage.Service

  @impl true
  def upload(_key, _bytes, _context), do: {:error, "Storage is unavailable"}
  @impl true
  defdelegate download(key, context), to: AshStorage.Service.Test
  @impl true
  defdelegate delete(key, context), to: AshStorage.Service.Test
  @impl true
  defdelegate exists?(key, context), to: AshStorage.Service.Test
  @impl true
  defdelegate url(key, context), to: AshStorage.Service.Test
  @impl true
  defdelegate direct_upload(key, context), to: AshStorage.Service.Test
end
