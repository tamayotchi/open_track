defmodule OpenTrack.AnalysisFixtures do
  @moduledoc false
  import ExUnit.Assertions
  alias OpenTrack.FakeReqLLM
  alias OpenTrack.Food

  def configure_ai do
    FakeReqLLM.reset()
    ExUnit.Callbacks.on_exit(&FakeReqLLM.reset/0)
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
    photo = create_unanalyzed_photo(owner, file)
    drain_analysis()
    Food.get_food_photo!(photo.id, actor: owner)
  end

  def create_unanalyzed_photo(owner, file \\ OpenTrack.Fixtures.upload()) do
    # Manual Oban testing keeps the real upload and enqueue behavior, but does
    # not execute jobs until the test explicitly drains the queue.
    Food.create_food_photo!(file, actor: owner)
  end

  def drain_analysis(opts \\ []) do
    Oban.drain_queue(
      Keyword.merge(
        [queue: :food_analysis, with_scheduled: true, with_recursion: true],
        opts
      )
    )
  end

  def assert_analysis(id, owner, status) do
    photo = Food.get_food_photo!(id, actor: owner)
    assert photo.analysis_status == status
    photo
  end
end
