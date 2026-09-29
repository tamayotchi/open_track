defmodule OpenTrack.Food.Analysis.PromptTest do
  use OpenTrack.DataCase
  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures
  alias OpenTrack.FakeReqLLM
  alias OpenTrack.Food

  setup do
    configure_ai()
    %{owner: user()}
  end

  test "the prompt action supplies the fixed model, stored image, and structured output schema",
       %{
         owner: owner
       } do
    parent = self()

    FakeReqLLM.stub(fn model, context, schema, opts ->
      send(parent, {:generation, model, context, schema, opts})
      response()
    end)

    photo = create_unanalyzed_photo(owner)

    assert {:ok, %{total_calories: 520.0, total_protein_g: 32.0, total_mass_g: 350.0}} =
             Food.analyze_food_photo(photo.id, actor: owner)

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

  test "background provider failures do not persist raw details", %{owner: owner} do
    FakeReqLLM.stub(fn _, _, _, _ -> {:error, "private-provider-error"} end)

    photo = create_analyzed_photo(owner)
    failed = await_photo(photo.id, owner, :failed)
    assert is_nil(failed.analysis)
    refute inspect(failed) =~ "private-provider-error"
  end

  test "the background task saves failures for raised, thrown, and exit errors", %{
    owner: owner
  } do
    for outcome <- [:raise, :throw, :exit] do
      FakeReqLLM.stub(fn _, _, _, _ ->
        case outcome do
          :raise -> raise "private-provider-error"
          :throw -> throw("private-provider-error")
          :exit -> exit("private-provider-error")
        end
      end)

      photo = create_analyzed_photo(owner)
      failed = await_photo(photo.id, owner, :failed)
      assert is_nil(failed.analysis)
      refute inspect(failed) =~ "private-provider-error"
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
      failed = await_photo(photo.id, owner, :failed)
      assert is_nil(failed.analysis)
    end
  end
end
