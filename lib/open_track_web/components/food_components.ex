defmodule OpenTrackWeb.FoodComponents do
  @moduledoc "Presentation of Ash food photo records. No inference or storage operations."
  use OpenTrackWeb, :html

  attr :id, :string, required: true
  attr :photo, OpenTrack.Food.FoodPhoto, required: true

  def photo_card(assigns) do
    ~H"""
    <article id={@id} class="photo-card" data-analysis-status={@photo.analysis_status}>
      <.photo_image photo={@photo} />
      <div class="photo-caption">
        <h3>Food moment</h3>
        <time datetime={DateTime.to_iso8601(@photo.inserted_at)}>
          {Calendar.strftime(@photo.inserted_at, "%b %-d, %Y · %H:%M UTC")}
        </time>
        <button
          type="button"
          phx-click="delete-photo"
          phx-value-id={@photo.id}
          data-confirm="Delete this photo permanently?"
          class="text-button"
          aria-label="Delete photo"
        >
          <.icon name="hero-trash" class="size-4" />
        </button>
      </div>
      <div class="border-t-2 border-black/10 p-4">
        <p class="flex items-center gap-2 text-sm font-semibold" role="status">
          {analysis_label(@photo)}
        </p>
        <details
          :if={@photo.analysis_status == :completed && @photo.analysis["food_detected"] == true}
          id={"#{@id}-analysis"}
          class="mt-3 text-sm"
        >
          <summary class="cursor-pointer font-semibold transition-colors hover:text-green-800">
            AI food details
          </summary>
          <div class="mt-3 space-y-3">
            <p>{@photo.analysis["description"]}</p>
            <dl class="grid grid-cols-3 gap-2">
              <div>
                <dt class="text-xs opacity-70">Calories</dt>
                <dd class="font-bold">{number(@photo.analysis["total_calories"])} kcal</dd>
              </div>
              <div>
                <dt class="text-xs opacity-70">Protein</dt>
                <dd class="font-bold">{number(@photo.analysis["total_protein_g"])} g</dd>
              </div>
              <div>
                <dt class="text-xs opacity-70">Edible mass</dt>
                <dd class="font-bold">{number(@photo.analysis["total_mass_g"])} g</dd>
              </div>
            </dl>
            <ul class="space-y-1">
              <li
                :for={item <- @photo.analysis["ingredients"] || []}
                class="flex justify-between gap-3"
              >
                <span>{item["name"]}</span><span>~{number(item["grams"])} g</span>
              </li>
            </ul>
            <p class="text-xs opacity-70">
              Rough photo estimates, not measurements or proof of what you ate.
            </p>
          </div>
        </details>
      </div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :photo, OpenTrack.Food.FoodPhoto, required: true

  def food_log_row(assigns) do
    ~H"""
    <tr id={@id} data-analysis-status={@photo.analysis_status}>
      <td><.photo_image photo={@photo} /></td>
      <td>
        <time datetime={DateTime.to_iso8601(@photo.inserted_at)}>
          {Calendar.strftime(@photo.inserted_at, "%b %-d, %Y · %H:%M")}
        </time>
      </td>
      <td>
        <span role="status">{analysis_label(@photo)}</span>
        <span
          :if={@photo.analysis_status == :completed && @photo.analysis["food_detected"] == true}
          class="block text-xs"
        >
          ~{number(@photo.analysis["total_protein_g"])} g protein · AI estimate
        </span>
        <button
          type="button"
          phx-click="delete-photo"
          phx-value-id={@photo.id}
          data-confirm="Delete this photo permanently?"
          class="text-button"
          aria-label="Delete photo"
        >
          <.icon name="hero-trash" class="size-4" />
        </button>
      </td>
    </tr>
    """
  end

  defp analysis_label(%{analysis_status: :completed, analysis: %{"food_detected" => false}}),
    do: "Saved · No food identified"

  defp analysis_label(%{analysis_status: :completed, analysis: %{"total_calories" => calories}}),
    do: "~#{number(calories)} kcal · AI estimate"

  defp analysis_label(%{analysis_status: :failed}),
    do: "Saved · Analysis failed · Not retried"

  defp analysis_label(_), do: "Saved · Not analyzed"
  defp number(value) when is_number(value), do: value |> round() |> Integer.to_string()
  defp number(_), do: "—"

  attr :photo, OpenTrack.Food.FoodPhoto, required: true

  defp photo_image(assigns) do
    ~H"""
    <img
      src={@photo.image_url}
      alt="Saved food moment"
      class="food-image"
      loading="lazy"
    />
    """
  end
end
