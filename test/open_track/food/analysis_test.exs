defmodule OpenTrack.Food.AnalysisTest do
  use OpenTrack.DataCase
  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures
  alias Ash.Resource.Info
  alias AshStorage.Service.Test, as: TestStorage
  alias OpenTrack.FakeReqLLM
  alias OpenTrack.Food
  alias OpenTrack.Food.Analysis

  setup do
    configure_ai()
    %{owner: user()}
  end

  test "the prompt uses the fixed model and stored image, returning a typed estimate without saving",
       %{owner: owner} do
    action = Info.action(Analysis, :analyze)
    assert {AshAi.Actions.Prompt, opts} = action.run
    assert opts[:tools] == false
    assert opts[:req_llm] == FakeReqLLM
    parent = self()

    FakeReqLLM.stub(fn model, context, schema, opts ->
      refute Repo.in_transaction?()
      send(parent, {:generation, model, context, schema, opts})
      response()
    end)

    photo = create_unanalyzed_photo(owner)

    assert {:ok, %Analysis.Estimate{} = estimate} =
             Food.analyze_food_photo(photo.id, actor: owner)

    assert estimate.total_calories == 520.0
    assert estimate.total_protein_g == 32.0
    assert estimate.total_mass_g == 350.0
    assert estimate.ingredients == [%{name: "Chicken rice bowl", grams: 350.0}]
    assert is_nil(assert_analysis(photo.id, owner, :not_analyzed).analysis)

    assert_receive {:generation, "openrouter:google/gemini-3.1-flash-lite", context, schema, []}
    schema = schema["properties"]["result"]

    for field <- ~w(total_calories total_protein_g total_mass_g)a do
      assert schema.properties[field].type == :number
    end

    assert schema.required |> Enum.map(&Atom.to_string/1) |> Enum.sort() ==
             Enum.sort(Map.keys(prediction()))

    ingredient_schema = schema.properties.ingredients.items
    assert ingredient_schema.type == :object
    assert ingredient_schema.properties.grams.type == :number
    assert Enum.sort(ingredient_schema.required) == [:grams, :name]
    refute Map.has_key?(schema.properties.ingredients, :maxItems)
    refute String.contains?(inspect(context), [owner.id, photo.id])
    assert [%{role: :system}, %{role: :user, content: [image]}] = context.messages
    assert image.type == :image
    assert image.media_type == "image/png"
    assert image.data == image_bytes()
  end

  test "analysis accepts only a valid photo ID, not caller-supplied image bytes", %{owner: owner} do
    parent = self()
    FakeReqLLM.stub(fn _, _, _, _ -> send(parent, :unexpected_request) end)
    photo = create_unanalyzed_photo(owner)

    for id <- [nil, "not-a-uuid"] do
      assert {:error, _} = Food.analyze_food_photo(id, actor: owner)
    end

    assert {:error, _} =
             Food.analyze_food_photo(photo.id, %{image: image_bytes(), content_type: "image/png"},
               actor: owner
             )

    assert_analysis(photo.id, owner, :not_analyzed)
    refute_receive :unexpected_request
  end

  test "non-owners and anonymous actors cannot load the image or reach the provider", %{
    owner: owner
  } do
    photo = create_unanalyzed_photo(owner)
    TestStorage.reset!()
    parent = self()
    FakeReqLLM.stub(fn _, _, _, _ -> send(parent, :unexpected_request) end)

    for actor <- [user(), nil] do
      assert catch_error(Food.analyze_food_photo!(photo.id, actor: actor))
    end

    assert_analysis(photo.id, owner, :not_analyzed)
    refute_receive :unexpected_request
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
      assert {:ok, %{total_calories: 520.0}} = Food.analyze_food_photo(photo.id, actor: owner)
      assert_analysis(photo.id, owner, :not_analyzed)
    end
  end
end
