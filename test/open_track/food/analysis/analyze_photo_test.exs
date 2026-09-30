defmodule OpenTrack.Food.Analysis.AnalyzePhotoTest do
  use OpenTrack.DataCase
  use Oban.Testing, repo: OpenTrack.Repo

  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures

  alias AshStorage.Service.Test, as: TestStorage
  alias OpenTrack.FakeReqLLM
  alias OpenTrack.Food
  alias OpenTrack.Food.FoodPhoto.AshOban.Worker.ProcessAnalysis, as: Worker

  @moduletag :capture_log

  setup do
    configure_ai()
    %{owner: user()}
  end

  test "upload queues one job containing only identifiers, without running AI", %{owner: owner} do
    parent = self()
    FakeReqLLM.stub(fn _, _, _, _ -> send(parent, :unexpected_request) end)
    photo = create_unanalyzed_photo(owner)

    assert [job] = all_enqueued(worker: Worker)
    assert job.queue == "food_analysis"
    assert job.max_attempts == 3
    assert job.args["primary_key"] == %{"id" => photo.id}
    refute Map.has_key?(job.args, "actor")
    refute inspect(job.args) =~ owner.id
    refute inspect(job.args) =~ image_bytes()
    refute inspect(job.args) =~ owner.hashed_password
    refute_receive :unexpected_request

    trigger = AshOban.Info.oban_trigger(Food.FoodPhoto, :process_analysis)
    refute trigger.scheduler_cron
    refute trigger.lock_for_update?
    assert trigger.read_action == :read
    assert trigger.worker_read_action == :read
    assert Ash.Resource.Info.action(Food.FoodPhoto, :read).pagination.keyset?
    assert trigger.default_actor == %{role: :food_analysis}
    assert Oban.config().engine == Oban.Engines.Lite
    assert Application.fetch_env!(:open_track, Oban)[:queues] == [food_analysis: 10]
  end

  test "new uploads save one validated estimate using the fixed model outside transactions", %{
    owner: owner
  } do
    parent = self()

    FakeReqLLM.stub(fn model, context, _schema, _opts ->
      refute Repo.in_transaction?()
      send(parent, {:request, model, context})
      response()
    end)

    photo = create_unanalyzed_photo(owner)
    assert %{success: 1, failure: 0} = drain_analysis()
    completed = assert_analysis(photo.id, owner, :completed)
    assert completed.analysis == prediction()
    assert completed.user_id == photo.user_id
    assert completed.inserted_at == photo.inserted_at
    assert_receive {:request, "openrouter:google/gemini-3.1-flash-lite", context}

    [_, %{content: [image]}] = context.messages
    assert image.data == image_bytes()
    refute inspect(context) =~ owner.id
    refute inspect(context) =~ photo.id
    refute_receive {:request, _, _}
  end

  test "uploads cannot supply analysis results or status", %{owner: owner} do
    for attrs <- [%{analysis: prediction()}, %{analysis_status: :completed}] do
      assert {:error, _} = Food.create_food_photo(upload(), attrs, actor: owner)
    end

    refute_enqueued(worker: Worker)
    assert Food.list_food_photos!(owner.id, page: [limit: 24]).results == []
  end

  test "provider errors retry, remain pending until exhaustion, and persist only safe errors", %{
    owner: owner
  } do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :attempt)
      {:error, "private-provider-error"}
    end)

    photo = create_unanalyzed_photo(owner)
    [job] = all_enqueued(worker: Worker)
    assert %{failure: 1, discard: 0} = drain_analysis(with_recursion: false)
    assert_analysis(photo.id, owner, :not_analyzed)
    assert Repo.get!(Oban.Job, job.id).state == "retryable"

    assert %{failure: 1, discard: 1} = drain_analysis()
    failed = assert_analysis(photo.id, owner, :failed)
    assert is_nil(failed.analysis)
    for _ <- 1..3, do: assert_receive(:attempt)
    refute_receive :attempt

    saved_job = Repo.get!(Oban.Job, job.id)
    assert saved_job.state == "discarded"
    assert saved_job.attempt == 3
    assert length(saved_job.errors) == 3
    assert inspect(saved_job.errors) =~ "Food photo analysis failed"
    refute inspect(saved_job.errors) =~ "private-provider-error"
    refute inspect(saved_job.errors) =~ image_bytes()
    loaded = Food.get_food_photo!(photo.id, actor: owner, load: [image: :blob])
    assert AshStorage.Operations.download(loaded.image.blob) == {:ok, image_bytes()}
  end

  test "a transient failure can succeed on a later attempt", %{owner: owner} do
    FakeReqLLM.stub(fn _, _, _, _ -> {:error, :timeout} end)
    photo = create_unanalyzed_photo(owner)
    assert %{failure: 1} = drain_analysis(with_recursion: false)
    assert_analysis(photo.id, owner, :not_analyzed)

    stub_prediction()
    assert %{success: 1, failure: 0} = drain_analysis()
    assert assert_analysis(photo.id, owner, :completed).analysis == prediction()
  end

  test "raised, thrown, and exit errors fail safely after retries", %{owner: owner} do
    for outcome <- [:raise, :throw, :exit] do
      FakeReqLLM.stub(fn _, _, _, _ ->
        case outcome do
          :raise -> raise "private-provider-error"
          :throw -> throw("private-provider-error")
          :exit -> exit("private-provider-error")
        end
      end)

      photo = create_unanalyzed_photo(owner)
      [job] = all_enqueued(worker: Worker)
      assert %{discard: 1} = drain_analysis()
      assert is_nil(assert_analysis(photo.id, owner, :failed).analysis)
      refute inspect(Repo.get!(Oban.Job, job.id).errors) =~ "private-provider-error"
    end
  end

  test "invalid structured results cannot be saved", %{owner: owner} do
    for estimate <- [
          prediction(%{"total_calories" => -1}),
          prediction(%{"total_protein_g" => 10_000}),
          %{"food_detected" => true}
        ] do
      stub_prediction(estimate)
      photo = create_analyzed_photo(owner)
      assert photo.analysis_status == :failed
      assert is_nil(photo.analysis)
    end
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
    assert photo.analysis_status == :completed
    assert photo.analysis["food_detected"] == false
  end

  test "missing stored bytes fail without reaching the provider", %{owner: owner} do
    parent = self()
    FakeReqLLM.stub(fn _, _, _, _ -> send(parent, :unexpected_request) end)
    photo = create_unanalyzed_photo(owner)
    TestStorage.reset!()

    assert %{discard: 1} = drain_analysis()
    assert is_nil(assert_analysis(photo.id, owner, :failed).analysis)
    refute_receive :unexpected_request
  end

  test "deletion while processing cannot recreate the photo", %{owner: owner} do
    photo = create_unanalyzed_photo(owner)

    FakeReqLLM.stub(fn _, _, _, _ ->
      assert :ok = Food.delete_food_photo(photo.id, actor: owner)
      response()
    end)

    assert %{cancelled: 1} = drain_analysis()
    assert Food.get_food_photo!(photo.id, actor: owner, not_found_error?: false) == nil
    assert TestStorage.list_keys() == []
  end

  test "duplicate enqueueing creates one pending job but replay runs analysis again", %{
    owner: owner
  } do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :attempt)
      response()
    end)

    photo = create_unanalyzed_photo(owner)

    for _ <- 1..3 do
      assert %Oban.Job{conflict?: true} =
               AshOban.run_trigger(photo, :process_analysis, actor: owner)
    end

    assert [job] = all_enqueued(worker: Worker)
    assert %{success: 1} = drain_analysis()
    assert_receive :attempt

    replacement = prediction(%{"total_calories" => 650})

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, :attempt)
      response(replacement)
    end)

    assert {:ok, _} = perform_job(Worker, job.args)
    assert_receive :attempt
    assert assert_analysis(photo.id, owner, :completed).analysis == replacement
    refute_receive :attempt
  end

  test "queued analysis runs for a failed photo", %{owner: owner} do
    photo = create_unanalyzed_photo(owner)
    Ash.Seed.update!(photo, %{analysis_status: :failed})

    stub_prediction()
    assert %{success: 1} = drain_analysis()
    assert assert_analysis(photo.id, owner, :completed).analysis == prediction()
  end

  test "exhausted retries clear previous results regardless of photo status", %{owner: owner} do
    photo = create_unanalyzed_photo(owner)
    Ash.Seed.update!(photo, %{analysis_status: :completed, analysis: prediction()})
    FakeReqLLM.stub(fn _, _, _, _ -> {:error, :timeout} end)

    assert %{discard: 1} = drain_analysis()
    assert is_nil(assert_analysis(photo.id, owner, :failed).analysis)
  end

  test "nutrition chart data contains only the requested user's completed photos within the UTC range",
       %{
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
      Food.nutrition_chart_data!(owner.id, ~U[2026-09-14 00:00:00Z], ~U[2026-09-21 00:00:00Z])

    assert photos |> Enum.map(&DateTime.truncate(&1.inserted_at, :second)) |> Enum.sort(DateTime) ==
             [
               ~U[2026-09-14 00:00:00Z],
               ~U[2026-09-20 12:00:00Z],
               ~U[2026-09-20 13:00:00Z]
             ]

    assert Enum.all?(photos, &(&1.analysis == prediction()))
  end

  test "storage failure rolls back both the photo and the queued job", %{owner: owner} do
    previous = Application.fetch_env!(:open_track, Food.FoodPhoto)
    on_exit(fn -> Application.put_env(:open_track, Food.FoodPhoto, previous) end)

    Application.put_env(:open_track, Food.FoodPhoto,
      storage: [service: {OpenTrack.UnavailableStorage, []}]
    )

    assert {:error, _} = Food.create_food_photo(upload(), actor: owner)
    assert Food.list_food_photos!(owner.id, page: [limit: 24]).results == []
    refute_enqueued(worker: Worker)
    assert TestStorage.list_keys() == []
  end

  test "enqueue failure rolls back creation before uploading any bytes", %{owner: owner} do
    # An infrastructure failure, inside the sandbox so the table is restored on exit.
    Repo.query!("DROP TABLE oban_jobs")

    assert_raise Ash.Error.Unknown, fn -> Food.create_food_photo(upload(), actor: owner) end
    assert Food.list_food_photos!(owner.id, page: [limit: 24]).results == []
    assert TestStorage.list_keys() == []
  end

  test "legacy jobs ignore stored user identities and run as internal analysis", %{owner: owner} do
    photo = create_unanalyzed_photo(owner)
    [job] = all_enqueued(worker: Worker)
    stub_prediction()

    # Jobs queued before the switch may still contain the old actor payload.
    for actor <- [nil, %{"id" => Ash.UUID.generate()}] do
      assert {:ok, _} = perform_job(Worker, Map.put(job.args, "actor", actor))
    end

    assert assert_analysis(photo.id, owner, :completed).analysis == prediction()
  end

  test "the internal actor is limited to reading photos and saving analysis", %{owner: owner} do
    photo = create_unanalyzed_photo(owner)
    actor = AshOban.Info.oban_trigger(Food.FoodPhoto, :process_analysis).default_actor

    assert Food.get_food_photo!(photo.id, actor: actor).id == photo.id
    assert {:error, _} = Food.delete_food_photo(photo.id, actor: actor)
    refute Ash.can?({Food.FoodPhoto, :create, %{uploaded_file: upload()}}, actor)
    assert {:error, _} = OpenTrack.Accounts.get_user_by_id(owner.id, actor: actor)
    assert Food.get_food_photo!(photo.id, actor: owner).id == photo.id
  end

  test "deleted photos cancel queued work without reaching the provider", %{owner: owner} do
    parent = self()
    FakeReqLLM.stub(fn _, _, _, _ -> send(parent, :unexpected_request) end)
    photo = create_unanalyzed_photo(owner)
    assert :ok = Food.delete_food_photo(photo.id, actor: owner)

    assert %{cancelled: 1} = drain_analysis()
    refute_receive :unexpected_request
    assert TestStorage.list_keys() == []
  end

  test "queued jobs survive an Oban supervisor restart", %{owner: owner} do
    photo = create_unanalyzed_photo(owner)
    [job] = all_enqueued(worker: Worker)
    assert :ok = Supervisor.terminate_child(OpenTrack.Supervisor, Oban)
    assert {:ok, _} = Supervisor.restart_child(OpenTrack.Supervisor, Oban)
    assert [%{id: id}] = all_enqueued(worker: Worker)
    assert id == job.id

    stub_prediction()
    assert %{success: 1} = drain_analysis()
    assert_analysis(photo.id, owner, :completed)
  end
end
