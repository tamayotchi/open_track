defmodule OpenTrackWeb.FoodComponents do
  @moduledoc "Presentation of Ash food photo records. No inference or storage operations."
  use OpenTrackWeb, :html

  attr :id, :string, required: true
  attr :photo, OpenTrack.Food.FoodPhoto, required: true

  def photo_card(assigns) do
    ~H"""
    <article id={@id} class="photo-card">
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
    </article>
    """
  end

  attr :id, :string, required: true
  attr :photo, OpenTrack.Food.FoodPhoto, required: true

  def food_log_row(assigns) do
    ~H"""
    <tr id={@id}>
      <td><.photo_image photo={@photo} /></td>
      <td>
        <time datetime={DateTime.to_iso8601(@photo.inserted_at)}>
          {Calendar.strftime(@photo.inserted_at, "%b %-d, %Y · %H:%M")}
        </time>
      </td>
      <td>
        Saved · Not analyzed
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
