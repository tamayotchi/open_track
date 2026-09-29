defmodule OpenTrackWeb.FoodLive do
  use OpenTrackWeb, :live_view

  alias OpenTrack.{Accounts, Food}
  alias OpenTrackWeb.{FoodComponents, NutritionChart, NutritionComponents}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(
       form: Food.form_to_create_food_photo(actor: user, as: "photo") |> to_form(),
       view_mode: :cards,
       today: today,
       days: 7,
       entries: [],
       settings: Accounts.get_settings_for_user!(user.id, actor: user, not_found_error?: false)
     )
     |> load_photos()
     |> load_nutrition()
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: 8_000_000
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply,
     assign(socket,
       page_title: if(socket.assigns.live_action == :add, do: "Add food", else: "Your journal")
     )}
  end

  @impl true
  def handle_event("set-view", %{"mode" => mode}, socket) when mode in ["cards", "table"] do
    {:noreply, assign(socket, view_mode: if(mode == "cards", do: :cards, else: :table))}
  end

  def handle_event("set-view", _params, socket), do: {:noreply, socket}
  def handle_event("validate-photo", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("save-photo", _params, socket) do
    case uploaded_entries(socket, :photo) do
      {[_], []} ->
        save_photo(socket)

      _ ->
        {:noreply, put_flash(socket, :error, "Choose a photo and wait for the upload to finish.")}
    end
  end

  def handle_event("load-more", _, socket) do
    {:noreply,
     if(socket.assigns.more?, do: load_photos(socket, socket.assigns.after), else: socket)}
  end

  def handle_event("delete-photo", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Food.delete_food_photo(id, actor: user) do
      :ok ->
        {:noreply,
         socket |> load_photos() |> load_nutrition() |> put_flash(:info, "Photo deleted.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete this photo.")}
    end
  end

  def handle_event("range", %{"days" => days}, socket) do
    {:noreply, socket |> assign(days: NutritionChart.days(days)) |> load_nutrition()}
  end

  defp save_photo(socket) do
    user = socket.assigns.current_user

    [result] =
      consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
        upload = %Plug.Upload{
          path: path,
          filename: Path.basename(entry.client_name),
          content_type: entry.client_type
        }

        {:ok, Food.create_food_photo(upload, actor: user)}
      end)

    case result do
      {:ok, _photo} ->
        {:noreply,
         socket
         |> load_photos()
         |> put_flash(:info, "Photo saved.")
         |> push_patch(to: ~p"/app")}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not save this photo. Choose a valid JPG, PNG, or WebP under 8 MB and try again."
         )}
    end
  end

  defp load_photos(socket, after_key \\ nil) do
    pagination = [limit: 24, count: true]
    pagination = if after_key, do: Keyword.put(pagination, :after, after_key), else: pagination

    page =
      Food.list_food_photos!(
        actor: socket.assigns.current_user,
        page: pagination,
        load: :image_url
      )

    socket
    |> assign(
      photo_count: page.count,
      more?: page.more?,
      after: if(page.results != [], do: List.last(page.results).__metadata__.keyset)
    )
    |> stream(:photos, page.results, reset: is_nil(after_key))
    |> stream(:food_log, page.results, reset: is_nil(after_key))
  end

  defp load_nutrition(socket) do
    today = socket.assigns.today
    from = DateTime.new!(Date.add(today, 1 - socket.assigns.days), ~T[00:00:00], "Etc/UTC")
    until = DateTime.new!(Date.add(today, 1), ~T[00:00:00], "Etc/UTC")

    entries =
      Food.nutrition_chart_data!(from, until, actor: socket.assigns.current_user)
      |> Enum.reduce(%{}, &add_photo_nutrition/2)
      |> Enum.map(fn {date, totals} -> Map.put(totals, :date, date) end)
      |> Enum.sort_by(& &1.date, Date)

    assign(socket, entries: entries, today: today)
  end

  defp add_photo_nutrition(
         %{
           analysis: %{
             "food_detected" => true,
             "total_calories" => calories,
             "total_protein_g" => protein
           }
         } = photo,
         days
       )
       when is_number(calories) and calories >= 0 and is_number(protein) and protein >= 0 do
    date = DateTime.to_date(photo.inserted_at)

    Map.update(days, date, %{calories: calories, protein: protein}, fn totals ->
      %{calories: totals.calories + calories, protein: totals.protein + protein}
    end)
  end

  defp add_photo_nutrition(_, days), do: days

  defp upload_error(:too_large), do: "Choose an image smaller than 8 MB."
  defp upload_error(:too_many_files), do: "Choose one photo at a time."
  defp upload_error(:not_accepted), do: "Please choose a JPG, PNG, or WebP image."
  defp upload_error(_), do: "This image could not be uploaded. Please try another."
end
