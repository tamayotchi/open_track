defmodule OpenTrack.AnalysisFixtures do
  @moduledoc false
  import ExUnit.Assertions
  alias OpenTrack.FakeReqLLM
  alias OpenTrack.Food

  def configure_ai do
    FakeReqLLM.reset()

    ExUnit.Callbacks.on_exit(fn ->
      # Stop background tasks before the sandbox and fake storage go away.
      Supervisor.terminate_child(OpenTrack.Supervisor, Food.AnalysisTasks)
      FakeReqLLM.reset()
      Supervisor.restart_child(OpenTrack.Supervisor, Food.AnalysisTasks)
    end)
  end

  def prediction(overrides \\ %{}) do
    Map.merge(
      %{
        "food_detected" => true,
        "description" => "Rice with chicken and vegetables; portions are approximate.",
        "total_calories" => 520,
        "total_protein_g" => 32,
        "total_mass_g" => 350,
        "ingredients" => [%{"name" => "Chicken rice bowl", "grams" => 350}]
      },
      overrides
    )
  end

  def response(estimate \\ prediction()) do
    {:ok, %{object: %{"result" => estimate}}}
  end

  def stub_prediction(estimate \\ prediction()) do
    FakeReqLLM.stub(fn _, _, _, _ -> response(estimate) end)
  end

  def create_analyzed_photo(owner, file \\ OpenTrack.Fixtures.upload()) do
    Food.create_food_photo!(file, actor: owner)
  end

  def create_unanalyzed_photo(owner, file \\ OpenTrack.Fixtures.upload()) do
    # Keep the real upload action, but leave notification delivery to the test.
    {photo, _notifications} =
      Food.create_food_photo!(file, actor: owner, return_notifications?: true)

    photo
  end

  def await_photo(id, owner, status, attempts \\ 200)
  def await_photo(_id, _owner, _status, 0), do: flunk("Analysis did not reach the expected state")

  def await_photo(id, owner, status, attempts) do
    photo = Food.get_food_photo!(id, actor: owner)

    if photo.analysis_status == status do
      photo
    else
      Process.sleep(10)
      await_photo(id, owner, status, attempts - 1)
    end
  end

  def eventually(fun, attempts \\ 200)
  def eventually(_fun, 0), do: flunk("Expected condition did not become true")

  def eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end
end
