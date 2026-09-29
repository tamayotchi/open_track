defmodule OpenTrack.FakeReqLLM do
  @moduledoc false

  # AI tests are synchronous; share their callbacks with background tasks.
  def stub(fun) when is_function(fun, 4) do
    Application.put_env(:open_track, __MODULE__, fun)
  end

  def reset do
    Application.delete_env(:open_track, __MODULE__)
  end

  def generate_object(model, context, schema, opts) do
    case Application.get_env(:open_track, __MODULE__) do
      nil -> {:error, :not_stubbed}
      fun -> fun.(model, context, schema, opts)
    end
  end
end
