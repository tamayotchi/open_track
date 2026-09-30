defmodule OpenTrack.Food.Analysis.QueueTest do
  use OpenTrack.DataCase
  use Oban.Testing, repo: OpenTrack.Repo

  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures

  alias Oban.Lifeline
  alias Oban.Peers.Isolated
  alias OpenTrack.FakeReqLLM
  alias OpenTrack.Food.FoodPhoto.AshOban.Worker.ProcessAnalysis, as: Worker

  @moduletag :capture_log

  setup do
    configure_ai()
    %{owner: user()}
  end

  test "the running queue limits execution to two jobs and then processes waiting uploads", %{
    owner: owner
  } do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      refute Repo.in_transaction?()
      send(parent, {:started, self()})

      receive do
        :finish -> response()
      end
    end)

    photos = for _ <- 1..3, do: create_unanalyzed_photo(owner)
    assert length(all_enqueued(worker: Worker)) == 3
    track_job_events()
    start_oban(queues: [food_analysis: 2])

    assert_receive {:started, first}, 3_000
    assert_receive {:started, second}, 3_000
    refute_receive {:started, _}
    assert_analysis(List.last(photos).id, owner, :not_analyzed)

    send(first, :finish)
    assert_receive {:finished, [:oban, :job, :stop], _}, 3_000
    assert_receive {:started, third}, 3_000
    send(second, :finish)
    send(third, :finish)
    for _ <- 1..2, do: assert_receive({:finished, [:oban, :job, :stop], _}, 3_000)
    for photo <- photos, do: assert_analysis(photo.id, owner, :completed)
  end

  test "a killed worker is retryable and its saved job runs after queue restart", %{owner: owner} do
    parent = self()

    FakeReqLLM.stub(fn _, _, _, _ ->
      send(parent, {:started, self()})

      receive do
        :never -> response()
      end
    end)

    photo = create_unanalyzed_photo(owner)
    track_job_events()
    start_oban(queues: [food_analysis: 2])
    assert_receive {:started, worker}, 3_000
    Process.exit(worker, :kill)
    assert_receive {:finished, [:oban, :job, :exception], job_id}, 3_000
    assert :ok = stop_supervised(__MODULE__)
    assert Repo.get!(Oban.Job, job_id).state == "retryable"
    assert_analysis(photo.id, owner, :not_analyzed)

    stub_prediction()
    assert %{success: 1} = drain_analysis()
    assert_analysis(photo.id, owner, :completed)
    assert Repo.get!(Oban.Job, job_id).attempt == 2
  end

  test "Lifeline rescues an abandoned executing job from SQLite", %{owner: owner} do
    photo = create_unanalyzed_photo(owner)
    [job] = all_enqueued(worker: Worker)

    # Simulate a node disappearing after claiming the job, without acknowledging it.
    job
    |> Ecto.Changeset.change(
      state: "executing",
      attempt: 1,
      attempted_at: DateTime.add(DateTime.utc_now(), -3, :hour)
    )
    |> Repo.update!()

    start_oban(queues: false)

    lifeline =
      start_supervised!(
        {Lifeline, conf: Oban.config(__MODULE__), rescue_after: {2, :hours}, interval: 60_000}
      )

    send(lifeline, :rescue)
    # Synchronize with the plugin after its rescue message, without sleeping/polling.
    :sys.get_state(lifeline)
    assert Repo.get!(Oban.Job, job.id).state == "available"

    stub_prediction()
    assert %{success: 1} = drain_analysis()
    assert_analysis(photo.id, owner, :completed)
  end

  defp start_oban(opts) do
    config =
      :open_track
      |> Application.fetch_env!(Oban)
      |> Keyword.merge(
        name: __MODULE__,
        testing: :disabled,
        peer: Isolated,
        plugins: [],
        lifeline: false,
        pruner: false,
        shutdown_grace_period: 100
      )
      |> Keyword.merge(opts)

    start_supervised!({Oban, config}, id: __MODULE__)
  end

  defp track_job_events do
    id = {__MODULE__, self()}

    :telemetry.attach_many(
      id,
      [[:oban, :job, :stop], [:oban, :job, :exception]],
      &__MODULE__.job_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  def job_event(event, _measurements, %{job: job}, parent) do
    send(parent, {:finished, event, job.id})
  end
end
