defmodule OpenTrack.Food.Analysis.AnalyzePhotoTest do
  use OpenTrack.DataCase
  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures
  alias Ash.Notifier.Notification
  alias Ash.Resource.Info
  alias AshStorage.Service.Test, as: TestStorage
  alias OpenTrack.FakeReqLLM
  alias OpenTrack.Food
  alias OpenTrack.Food.Analysis

  setup do
    configure_ai()
    %{owner: user()}
  end

  test "analysis is a single prompt-backed action accepting only a photo ID" do
    refute Info.action(Food.FoodPhoto, :analyze)
    assert Enum.map(Info.actions(Analysis), & &1.name) == [:analyze]

    action = Info.action(Analysis, :analyze)
    assert {AshAi.Actions.Prompt, opts} = action.run
    assert opts[:tools] == false
    assert opts[:req_llm] == FakeReqLLM
    assert action.returns == Analysis.Estimate
    refute action.transaction?
    assert Enum.map(action.arguments, & &1.name) == [:photo_id]
  end

  test "analysis returns an estimate without saving and calls AI outside a database transaction",
       %{
         owner: owner
       } do
    FakeReqLLM.stub(fn _, _, _, _ ->
      refute OpenTrack.Repo.in_transaction?()
      response()
    end)

    photo = create_unanalyzed_photo(owner)

    assert {:ok, %Analysis.Estimate{} = estimate} =
             Food.analyze_food_photo(photo.id, actor: owner)

    assert estimate.total_calories == 520.0
    unchanged = Food.get_food_photo!(photo.id, actor: owner)
    assert unchanged.analysis_status == :not_analyzed
    assert is_nil(unchanged.analysis)
  end

  test "callers cannot substitute image bytes for the stored photo", %{owner: owner} do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :unexpected_request)
      response()
    end)

    photo = create_unanalyzed_photo(owner)

    assert {:error, _} =
             Food.analyze_food_photo(photo.id, %{image: image_bytes(), content_type: "image/png"},
               actor: owner
             )

    assert Food.get_food_photo!(photo.id, actor: owner).analysis_status == :not_analyzed
    refute_receive :unexpected_request, 30
  end

  test "new uploads persist one validated estimate using the fixed model", %{owner: owner} do
    parent = self()

    FakeReqLLM.stub(fn model, context, _schema, _opts ->
      send(parent, {:request, model, context})
      response()
    end)

    photo = create_analyzed_photo(owner)
    completed = await_photo(photo.id, owner, :completed)
    assert completed.analysis == prediction()
    assert_receive {:request, "openrouter:google/gemini-3.1-flash-lite", context}

    [_, %{content: [image]}] = context.messages
    assert image.data == image_bytes()
    refute inspect(context) =~ owner.id
    refute inspect(context) =~ photo.id

    refute_receive {:request, _, _}, 30
  end

  test "non-owners and anonymous actors cannot analyze or update analysis", %{owner: owner} do
    photo = create_unanalyzed_photo(owner)
    estimate = prediction()

    for actor <- [user(), nil] do
      assert {:error, _} =
               Food.update_food_analysis(
                 photo.id,
                 %{analysis: estimate, analysis_status: :completed},
                 actor: actor
               )

      assert {:error, _} =
               Food.update_food_analysis(
                 photo.id,
                 %{analysis: nil, analysis_status: :failed},
                 actor: actor
               )

      assert catch_error(Food.analyze_food_photo!(photo.id, actor: actor))
    end

    assert Food.get_food_photo!(photo.id, actor: owner).analysis_status == :not_analyzed

    assert {:error, _} = Food.create_food_photo(upload(), %{analysis: prediction()}, actor: owner)

    assert {:error, _} =
             Food.create_food_photo(upload(), %{analysis_status: :completed}, actor: owner)
  end

  test "provider failures preserve bytes and do not persist raw errors", %{owner: owner} do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :attempt)
      {:error, "private-provider-error"}
    end)

    photo = create_analyzed_photo(owner)
    failed = await_photo(photo.id, owner, :failed)
    assert is_nil(failed.analysis)
    assert_receive :attempt
    refute_receive :attempt, 30
    refute inspect(failed) =~ "private-provider-error"
    loaded = Food.get_food_photo!(photo.id, actor: owner, load: [image: :blob])
    assert AshStorage.Operations.download(loaded.image.blob) == {:ok, image_bytes()}
  end

  test "non-food completes normally with a non-food result", %{owner: owner} do
    stub_prediction(
      prediction(%{
        "food_detected" => false,
        "description" => "No food visible.",
        "total_calories" => 0,
        "total_protein_g" => 0,
        "total_mass_g" => 0,
        "ingredients" => []
      })
    )

    photo = create_analyzed_photo(owner)
    result = await_photo(photo.id, owner, :completed)
    assert result.analysis["food_detected"] == false
  end

  test "an invalid AI estimate fails without saving results", %{owner: owner} do
    stub_prediction(prediction(%{"total_calories" => -1}))
    photo = create_analyzed_photo(owner)
    failed = await_photo(photo.id, owner, :failed)
    assert is_nil(failed.analysis)
  end

  test "analysis forwards stored bytes and MIME metadata without revalidating uploads", %{
    owner: owner
  } do
    file = upload()

    for {bytes, type} <- [
          {"not an image", "image/png"},
          {image_bytes(), "image/jpeg"},
          {image_bytes() <> :binary.copy(<<0>>, 8_000_001), "image/png"}
        ] do
      FakeReqLLM.stub(fn _model, context, _schema, _opts ->
        [_, %{content: [image]}] = context.messages
        assert image.data == bytes
        assert image.media_type == type
        response()
      end)

      File.write!(file.path, bytes)
      photo = create_unanalyzed_photo(owner, %{file | content_type: type})
      result = Food.analyze_food_photo(photo.id, actor: owner)

      assert match?({:ok, %{total_calories: 520.0}}, result),
             "Could not forward #{byte_size(bytes)} bytes with type #{type}"

      assert Food.get_food_photo!(photo.id, actor: owner).analysis_status == :not_analyzed
    end
  end

  test "missing stored bytes fail analysis without reaching the provider", %{owner: owner} do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :unexpected_request)
      response()
    end)

    photo = create_unanalyzed_photo(owner)
    TestStorage.reset!()

    assert :ok = Analysis.Notifier.notify(%Notification{data: photo, actor: owner})
    failed = await_photo(photo.id, owner, :failed)
    assert is_nil(failed.analysis)
    refute_receive :unexpected_request, 30
  end

  test "non-owners and anonymous actors cannot interfere with an in-flight analysis", %{
    owner: owner
  } do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, {:started, self()})

      receive do
        :finish -> response()
      end
    end)

    photo = create_analyzed_photo(owner)
    assert_receive {:started, task}, 2_000

    for actor <- [user(), nil] do
      assert catch_error(Food.analyze_food_photo!(photo.id, actor: actor))
    end

    assert Food.get_food_photo!(photo.id, actor: owner).analysis_status == :not_analyzed
    refute_receive {:started, _}, 30
    send(task, :finish)
    await_photo(photo.id, owner, :completed)
  end

  test "deletion while processing cannot recreate the photo", %{owner: owner} do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, {:started, self()})

      receive do
        :finish -> response()
      end
    end)

    photo = create_analyzed_photo(owner)
    assert_receive {:started, task}, 2_000
    monitor = Process.monitor(task)
    assert :ok = Food.delete_food_photo(photo.id, actor: owner)
    send(task, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^task, _}, 2_000
    assert Food.get_food_photo!(photo.id, actor: owner, not_found_error?: false) == nil
  end

  test "background analysis replaces results regardless of the previous status", %{owner: owner} do
    updated_estimate = prediction(%{"total_calories" => 650})
    stub_prediction(updated_estimate)

    for status <- [:not_analyzed, :completed, :failed] do
      photo =
        create_unanalyzed_photo(owner)
        |> Ash.Seed.update!(%{analysis_status: status, analysis: prediction()})

      assert :ok = Analysis.Notifier.notify(%Notification{data: photo, actor: owner})

      eventually(fn ->
        Food.get_food_photo!(photo.id, actor: owner).analysis == updated_estimate
      end)

      completed = Food.get_food_photo!(photo.id, actor: owner)
      assert completed.analysis_status == :completed
      assert completed.analysis == updated_estimate
    end
  end

  test "a failed reanalysis clears the previous estimate without deleting the photo", %{
    owner: owner
  } do
    photo =
      create_unanalyzed_photo(owner)
      |> Ash.Seed.update!(%{analysis_status: :completed, analysis: prediction()})

    FakeReqLLM.stub(fn _, _, _, _ -> {:error, "Provider unavailable"} end)
    assert :ok = Analysis.Notifier.notify(%Notification{data: photo, actor: owner})
    await_photo(photo.id, owner, :failed)

    failed = Food.get_food_photo!(photo.id, actor: owner, load: [image: :blob])
    assert failed.analysis_status == :failed
    assert is_nil(failed.analysis)
    assert AshStorage.Operations.download(failed.image.blob) == {:ok, image_bytes()}
  end

  test "nutrition chart data contains only completed owned photos within the UTC range", %{
    owner: owner
  } do
    for {actor, status, date} <- [
          {owner, :completed, ~U[2026-09-20 12:00:00Z]},
          {owner, :completed, ~U[2026-09-20 13:00:00Z]},
          {owner, :completed, ~U[2026-09-14 00:00:00Z]},
          {owner, :failed, ~U[2026-09-19 12:00:00Z]},
          {owner, :not_analyzed, ~U[2026-09-19 12:00:00Z]},
          {owner, :completed, ~U[2026-09-21 00:00:00Z]},
          {owner, :completed, ~U[2026-09-13 23:59:59Z]},
          {user(), :completed, ~U[2026-09-20 12:00:00Z]}
        ] do
      create_unanalyzed_photo(actor)
      |> Ash.Seed.update!(%{analysis_status: status, analysis: prediction(), inserted_at: date})
    end

    photos =
      Food.nutrition_chart_data!(~U[2026-09-14 00:00:00Z], ~U[2026-09-21 00:00:00Z], actor: owner)

    assert photos |> Enum.map(&DateTime.truncate(&1.inserted_at, :second)) |> Enum.sort(DateTime) ==
             [
               ~U[2026-09-14 00:00:00Z],
               ~U[2026-09-20 12:00:00Z],
               ~U[2026-09-20 13:00:00Z]
             ]

    assert Enum.all?(photos, &(&1.analysis == prediction()))
  end

  test "a generation timeout marks analysis failed", %{owner: owner} do
    FakeReqLLM.stub(fn _, _, _, _ -> {:error, :timeout} end)
    photo = create_analyzed_photo(owner)
    assert is_nil(await_photo(photo.id, owner, :failed).analysis)
  end

  test "storage failure never starts an AI request", %{owner: owner} do
    previous = Application.fetch_env!(:open_track, Food.FoodPhoto)
    on_exit(fn -> Application.put_env(:open_track, Food.FoodPhoto, previous) end)

    Application.put_env(:open_track, Food.FoodPhoto,
      storage: [service: {OpenTrack.UnavailableStorage, []}]
    )

    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :unexpected_request)
      response()
    end)

    assert {:error, _} = Food.create_food_photo(upload(), actor: owner)

    assert Food.list_food_photos!(actor: owner, page: [limit: 24]).results == []
    refute_receive :unexpected_request, 30
  end

  test "the notifier uses the supplied actor for analysis and task-start failures", %{
    owner: owner
  } do
    photo = create_unanalyzed_photo(owner)
    notification = %Notification{data: photo, actor: user()}
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :unexpected_request)
      response()
    end)

    assert :ok = Analysis.Notifier.notify(notification)
    eventually(fn -> Task.Supervisor.children(Food.AnalysisTasks) == [] end)
    assert Food.get_food_photo!(photo.id, actor: owner).analysis_status == :not_analyzed

    assert :ok = Supervisor.terminate_child(OpenTrack.Supervisor, Food.AnalysisTasks)
    assert :ok = Analysis.Notifier.notify(notification)
    assert Food.get_food_photo!(photo.id, actor: owner).analysis_status == :not_analyzed
    refute_receive :unexpected_request, 30
  end

  test "an unavailable task supervisor preserves the upload and marks analysis failed", %{
    owner: owner
  } do
    assert :ok = Supervisor.terminate_child(OpenTrack.Supervisor, Food.AnalysisTasks)
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :unexpected_request)
      response()
    end)

    photo = create_analyzed_photo(owner)
    loaded = Food.get_food_photo!(photo.id, actor: owner, load: [image: :blob])
    assert loaded.analysis_status == :failed
    assert AshStorage.Operations.download(loaded.image.blob) == {:ok, image_bytes()}
    refute_receive :unexpected_request, 30
  end

  test "deleted photos never reach the provider", %{owner: owner} do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :unexpected_request)
      response()
    end)

    deleted = create_unanalyzed_photo(owner)
    assert :ok = Food.delete_food_photo(deleted.id, actor: owner)
    assert catch_error(Food.analyze_food_photo!(deleted.id, actor: owner))
    refute_receive :unexpected_request, 30
  end

  test "supervisor restart terminates tasks without replay", %{
    owner: owner
  } do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, {:started, self()})

      receive do
        :never -> response()
      end
    end)

    photos = for _ <- 1..2, do: create_analyzed_photo(owner)
    assert_receive {:started, task1}, 2_000
    assert_receive {:started, task2}, 2_000
    monitors = [Process.monitor(task1), Process.monitor(task2)]
    old_supervisor = Process.whereis(Food.AnalysisTasks)
    Process.exit(old_supervisor, :kill)
    for ref <- monitors, do: assert_receive({:DOWN, ^ref, :process, _, _}, 2_000)
    eventually(fn -> Process.whereis(Food.AnalysisTasks) not in [nil, old_supervisor] end)
    refute_receive {:started, _}, 30

    for photo <- photos do
      saved = Food.get_food_photo!(photo.id, actor: owner)
      assert saved.analysis_status == :not_analyzed
      assert is_nil(saved.analysis)
    end
  end

  test "task limit preserves uploads without queuing and releases capacity after completion", %{
    owner: owner
  } do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, {:started, self()})

      receive do
        :finish -> response()
      end
    end)

    photos = for _ <- 1..3, do: create_analyzed_photo(owner)
    assert_receive {:started, task1}, 2_000
    assert_receive {:started, task2}, 2_000
    refute_receive {:started, _}, 30
    rejected = List.last(photos)
    assert Food.get_food_photo!(rejected.id, actor: owner).analysis_status == :failed
    loaded = Food.get_food_photo!(rejected.id, actor: owner, load: [image: :blob])
    assert AshStorage.Operations.download(loaded.image.blob) == {:ok, image_bytes()}
    assert length(Task.Supervisor.children(Food.AnalysisTasks)) == 2

    send(task1, :finish)
    send(task2, :finish)
    for photo <- Enum.take(photos, 2), do: await_photo(photo.id, owner, :completed)
    eventually(fn -> Task.Supervisor.children(Food.AnalysisTasks) == [] end)
    assert Food.get_food_photo!(rejected.id, actor: owner).analysis_status == :failed
    refute_receive {:started, _}, 30

    photo = create_analyzed_photo(owner)
    assert_receive {:started, task}, 2_000
    send(task, :finish)
    await_photo(photo.id, owner, :completed)
    assert length(Food.list_food_photos!(actor: owner, page: [limit: 24]).results) == 4
  end
end
