defmodule OpenTrack.Food.Analysis.Process do
  @moduledoc "Generate and persist an estimate without holding a database transaction."
  use Ash.Resource.Change

  alias OpenTrack.Food

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, &apply_estimate(&1, context.actor))
  end

  defp apply_estimate(changeset, actor) do
    case estimate(changeset.data.id, actor) do
      {:ok, estimate} ->
        Ash.Changeset.force_change_attributes(changeset, %{
          analysis: Map.from_struct(estimate),
          analysis_status: :completed
        })

      :error ->
        Ash.Changeset.add_error(changeset, "Food photo analysis failed")
    end
  end

  defp estimate(id, actor) do
    case Food.analyze_food_photo(id, actor: actor) do
      {:ok, estimate} -> {:ok, estimate}
      {:error, _} -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end
end
