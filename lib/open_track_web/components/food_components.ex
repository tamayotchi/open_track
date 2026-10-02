defmodule OpenTrackWeb.FoodComponents do
  @moduledoc "Presentation of Ash food photo records. No inference or storage operations."
  use OpenTrackWeb, :html

  alias OpenTrackWeb.Timezones

  attr :id, :string, required: true
  attr :photo, OpenTrack.Food.FoodPhoto, required: true

  attr :timezone, :string, default: "Etc/UTC"

  attr :editable, :boolean, default: true

  attr :user, OpenTrack.Accounts.User, default: nil

  def photo_card(assigns) do
    assigns =
      assign(
        assigns,
        :uploaded_at,
        Timezones.local_datetime(assigns.photo.inserted_at, assigns.timezone)
      )

    ~H"""
    <article id={@id} class="photo-card" data-analysis-status={@photo.analysis_status}>
      <header :if={@user} class="border-b-2 border-black p-4">
        <.link
          navigate={~p"/app/profile/#{@user.nickname}"}
          class="group flex min-w-0 items-center gap-3"
          aria-label={"View #{@user.nickname}'s journal"}
        >
          <img
            :if={@user.avatar_url}
            src={@user.avatar_url}
            alt=""
            loading="lazy"
            class="size-11 shrink-0 rounded-full border-2 border-black object-cover"
          />
          <span
            :if={!@user.avatar_url}
            class="grid size-11 shrink-0 place-items-center rounded-full border-2 border-black bg-[#b7d96d]"
          >
            <.icon name="hero-user" class="size-5" />
          </span>
          <span class="min-w-0">
            <span class="block truncate text-sm font-bold underline-offset-4 group-hover:underline">
              {@user.nickname}
            </span>
            <span class="text-xs text-muted">Shared a food moment</span>
          </span>
          <.icon
            name="hero-arrow-up-right"
            class="ml-auto size-4 shrink-0 transition-transform group-hover:-translate-y-0.5"
          />
        </.link>
      </header>
      <.photo_image photo={@photo} />
      <div class="photo-caption">
        <h3>Food moment</h3>
        <time datetime={DateTime.to_iso8601(@photo.inserted_at)}>
          {Calendar.strftime(@uploaded_at, "%b %-d, %Y · %H:%M %Z")}
        </time>
        <button
          :if={@editable}
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

  attr :timezone, :string, default: "Etc/UTC"

  attr :editable, :boolean, default: true

  def food_log_row(assigns) do
    assigns =
      assign(
        assigns,
        :uploaded_at,
        Timezones.local_datetime(assigns.photo.inserted_at, assigns.timezone)
      )

    ~H"""
    <tr id={@id} data-analysis-status={@photo.analysis_status}>
      <td><.photo_image photo={@photo} /></td>
      <td>
        <time datetime={DateTime.to_iso8601(@photo.inserted_at)}>
          {Calendar.strftime(@uploaded_at, "%b %-d, %Y · %H:%M %Z")}
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
          :if={@editable}
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
