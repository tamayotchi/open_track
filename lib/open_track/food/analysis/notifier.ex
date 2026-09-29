defmodule OpenTrack.Food.Analysis.Notifier do
  @moduledoc "Run background analysis after upload and save its outcome."
  use Ash.Notifier
  alias OpenTrack.Food

  @failed_analysis %{analysis: nil, analysis_status: :failed}

  @impl true
  def notify(%{data: %{id: id}, actor: actor}) do
    started =
      try do
        Task.Supervisor.start_child(Food.AnalysisTasks, fn -> analyze_and_save(id, actor) end)
      catch
        :exit, _ -> {:error, :task_start_failed}
      end

    case started do
      {:ok, _pid} ->
        :ok

      {:error, _} ->
        Food.update_food_analysis(id, @failed_analysis, actor: actor)
        :ok
    end
  end

  defp analyze_and_save(id, actor) do
    attrs =
      try do
        case Food.analyze_food_photo(id, actor: actor) do
          {:ok, estimate} -> %{analysis: Map.from_struct(estimate), analysis_status: :completed}
          {:error, _} -> @failed_analysis
        end
      rescue
        _ -> @failed_analysis
      catch
        _, _ -> @failed_analysis
      end

    Food.update_food_analysis(id, attrs, actor: actor)
  end
end
