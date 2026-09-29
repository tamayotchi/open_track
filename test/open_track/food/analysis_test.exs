defmodule OpenTrack.Food.AnalysisTest do
  use OpenTrack.DataCase
  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures
  alias AshStorage.Service.Test, as: TestStorage
  alias OpenTrack.FakeReqLLM
  alias OpenTrack.Food
  alias OpenTrack.Food.Analysis.Estimate

  setup do
    configure_ai()
    %{owner: user()}
  end

  test "analysis returns a typed estimate without changing the stored photo", %{
    owner: owner
  } do
    photo = create_unanalyzed_photo(owner, %{upload() | content_type: "image/jpeg"})

    FakeReqLLM.stub(fn _model, context, _schema, _opts ->
      refute OpenTrack.Repo.in_transaction?()
      [_, %{content: [image]}] = context.messages
      assert image.type == :image
      assert image.media_type == "image/jpeg"
      assert image.data == image_bytes()
      response()
    end)

    assert {:ok, %Estimate{} = estimate} = Food.analyze_food_photo(photo.id, actor: owner)
    assert estimate.ingredients == [%{name: "Chicken rice bowl", grams: 350.0}]
    unchanged = Food.get_food_photo!(photo.id, actor: owner)
    assert unchanged.analysis_status == :not_analyzed
    assert is_nil(unchanged.analysis)
  end

  test "analysis updates preserve omitted fields and persist atom-keyed estimates", %{
    owner: owner
  } do
    photo = create_unanalyzed_photo(owner)
    estimate = prediction() |> Jason.encode!() |> Jason.decode!(keys: :atoms!)

    completed =
      Food.update_food_analysis!(
        photo.id,
        %{analysis: estimate, analysis_status: :completed},
        actor: owner
      )

    assert completed.analysis == prediction()
    assert completed.analysis_status == :completed
    assert completed.user_id == photo.user_id
    assert completed.inserted_at == photo.inserted_at

    replacement = prediction(%{"total_calories" => 650})
    updated = Food.update_food_analysis!(photo.id, %{analysis: replacement}, actor: owner)
    assert updated.analysis == replacement
    assert updated.analysis_status == :completed

    status_only =
      Food.update_food_analysis!(photo.id, %{analysis_status: :completed}, actor: owner)

    assert status_only.analysis == replacement
    unchanged = Food.update_food_analysis!(photo.id, %{}, actor: owner)
    assert unchanged.analysis == replacement
    assert unchanged.analysis_status == :completed
    assert Food.get_food_photo!(photo.id, actor: owner).analysis == replacement
  end

  test "inconsistent patches are rejected and failure explicitly clears the estimate", %{
    owner: owner
  } do
    photo = create_unanalyzed_photo(owner)

    Food.update_food_analysis!(
      photo.id,
      %{analysis: prediction(), analysis_status: :completed},
      actor: owner
    )

    for attrs <- [
          %{analysis: nil},
          %{analysis_status: :failed},
          %{analysis_status: :not_analyzed},
          %{analysis_status: nil},
          %{analysis_status: :unknown},
          %{analysis: prediction(), analysis_status: :failed}
        ] do
      assert {:error, _} = Food.update_food_analysis(photo.id, attrs, actor: owner)
      unchanged = Food.get_food_photo!(photo.id, actor: owner)
      assert unchanged.analysis == prediction()
      assert unchanged.analysis_status == :completed
    end

    failed =
      Food.update_food_analysis!(
        photo.id,
        %{analysis: nil, analysis_status: :failed},
        actor: owner
      )

    assert is_nil(failed.analysis)
    assert failed.analysis_status == :failed
    loaded = Food.get_food_photo!(photo.id, actor: owner, load: [image: :blob])
    assert is_nil(loaded.analysis)
    assert loaded.analysis_status == :failed
    assert AshStorage.Operations.download(loaded.image.blob) == {:ok, image_bytes()}
  end

  test "completion requires an estimate and other statuses require no estimate", %{
    owner: owner
  } do
    photo = create_unanalyzed_photo(owner)

    for attrs <- [
          %{analysis_status: :completed},
          %{analysis: nil, analysis_status: :completed},
          %{analysis: prediction()},
          %{analysis: prediction(), analysis_status: :not_analyzed},
          %{analysis: prediction(), analysis_status: :failed}
        ] do
      assert {:error, _} = Food.update_food_analysis(photo.id, attrs, actor: owner)
      unchanged = Food.get_food_photo!(photo.id, actor: owner)
      assert unchanged.analysis_status == :not_analyzed
      assert is_nil(unchanged.analysis)
    end

    failed = Food.update_food_analysis!(photo.id, %{analysis_status: :failed}, actor: owner)
    assert failed.analysis_status == :failed
    assert is_nil(failed.analysis)

    reset = Food.update_food_analysis!(photo.id, %{analysis_status: :not_analyzed}, actor: owner)
    assert reset.analysis_status == :not_analyzed
    assert is_nil(reset.analysis)
  end

  test "analysis updates accept only analysis attributes", %{owner: owner} do
    photo = create_unanalyzed_photo(owner)
    other = user()

    for attrs <- [%{user_id: other.id}, %{estimate: prediction()}] do
      assert {:error, _} = Food.update_food_analysis(photo.id, attrs, actor: owner)
    end

    unchanged = Food.get_food_photo!(photo.id, actor: owner)
    assert unchanged.user_id == owner.id
    assert unchanged.analysis_status == :not_analyzed
    assert is_nil(unchanged.analysis)
  end

  test "non-owners and anonymous actors cannot load the image or reach the provider", %{
    owner: owner
  } do
    photo = create_unanalyzed_photo(owner)
    TestStorage.reset!()
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :unexpected_request)
      response()
    end)

    for actor <- [user(), nil] do
      assert catch_error(Food.analyze_food_photo!(photo.id, actor: actor))
    end

    assert Food.get_food_photo!(photo.id, actor: owner).analysis_status == :not_analyzed
    refute_receive :unexpected_request, 30
  end

  test "a valid photo ID is required before requesting an estimate", %{owner: owner} do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :unexpected_request)
      response()
    end)

    for id <- [nil, "not-a-uuid"] do
      assert {:error, _} = Food.analyze_food_photo(id, actor: owner)
    end

    refute_receive :unexpected_request, 30
  end
end
