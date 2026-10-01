defmodule OpenTrackWeb.FoodLive do
  use OpenTrackWeb, :live_view

  alias OpenTrack.{Accounts, Food}
  alias OpenTrackWeb.{FoodComponents, NutritionChart, NutritionComponents, Timezones}

  @impl true
  def mount(_params, _session, %{assigns: %{live_action: :profile}} = socket) do
    {:ok, assign(socket, public_profile?: true)}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    settings =
      Accounts.get_user_by_id!(user.id, actor: user, load: :public_settings).public_settings

    timezone = settings.timezone || Timezones.utc()

    {:ok,
     socket
     |> assign(
       public_profile?: false,
       profile: nil,
       journal_user_id: user.id,
       form: Food.form_to_create_food_photo(actor: user, as: "photo") |> to_form(),
       view_mode: :cards,
       today: Timezones.today(timezone),
       timezone: timezone,
       timezone_label: Timezones.label(timezone),
       days: 7,
       entries: [],
       settings: settings
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
  def handle_params(
        %{"nickname" => nickname},
        _uri,
        %{assigns: %{live_action: :profile}} = socket
      ) do
    profile =
      Accounts.get_public_profile!(nickname,
        not_found_error?: false,
        load: [:avatar_url, :followers_count, :following_count]
      )

    {:noreply, load_public_profile(socket, profile)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     assign(socket,
       page_title: if(socket.assigns.live_action == :add, do: "Add food", else: "Your journal")
     )}
  end

  @impl true
  def handle_event(_event, _params, %{assigns: %{public_profile?: true, profile: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event(event, _params, %{assigns: %{public_profile?: true}} = socket)
      when event in ["follow", "unfollow"] do
    user = socket.assigns.current_user
    profile = socket.assigns.profile

    if user && user.id != profile.id do
      result =
        case event do
          "follow" -> Accounts.follow_user(profile.id, actor: user)
          "unfollow" -> unfollow(profile.id, user)
        end

      case result do
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not update your follow. Please try again.")}

        _ ->
          profile =
            Accounts.get_public_profile!(profile.nickname,
              load: [:avatar_url, :followers_count, :following_count]
            )

          {:noreply, socket |> assign(:profile, profile) |> assign_follow(profile)}
      end
    else
      {:noreply, socket}
    end
  end

  # The only public-profile mutations are the visitor's own follow connection.
  # Journal mutations remain forbidden, including for the profile owner.
  def handle_event(event, _params, %{assigns: %{public_profile?: true}} = socket)
      when event not in ["set-view", "load-more", "range"] do
    {:noreply, socket}
  end

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

  defp load_public_profile(socket, nil) do
    socket
    |> assign(
      profile: nil,
      journal_user_id: nil,
      page_title: "Profile not found",
      settings: nil,
      entries: [],
      photo_count: 0,
      more?: false,
      after: nil
    )
    |> stream(:photos, [], reset: true)
    |> stream(:food_log, [], reset: true)
  end

  defp load_public_profile(socket, profile) do
    settings = profile.public_settings
    timezone = settings.timezone || Timezones.utc()

    socket
    |> assign(
      profile: profile,
      journal_user_id: profile.id,
      page_title: "#{profile.nickname}'s journal",
      view_mode: :cards,
      timezone: timezone,
      timezone_label: Timezones.label(timezone),
      days: 7,
      settings: settings
    )
    |> assign_follow(profile)
    |> load_photos()
    |> load_nutrition()
  end

  defp assign_follow(socket, profile) do
    user = socket.assigns.current_user

    follow =
      if user && user.id != profile.id do
        Accounts.get_follow!(profile.id, actor: user, not_found_error?: false)
      end

    assign(socket, following?: not is_nil(follow))
  end

  defp unfollow(profile_id, user) do
    case Accounts.get_follow(profile_id, actor: user, not_found_error?: false) do
      {:ok, nil} -> :ok
      {:ok, follow} -> Accounts.unfollow_user(follow.id, actor: user)
      {:error, error} -> {:error, error}
    end
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
      Food.list_food_photos!(socket.assigns.journal_user_id,
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
    timezone = socket.assigns.timezone
    today = Timezones.today(timezone)
    {from, until} = Timezones.utc_range(Date.add(today, 1 - socket.assigns.days), today, timezone)

    entries =
      Food.nutrition_chart_data!(socket.assigns.journal_user_id, from, until)
      |> Enum.reduce(%{}, &add_photo_nutrition(&1, &2, timezone))
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
         days,
         timezone
       )
       when is_number(calories) and calories >= 0 and is_number(protein) and protein >= 0 do
    date = Timezones.local_date(photo.inserted_at, timezone)

    Map.update(days, date, %{calories: calories, protein: protein}, fn totals ->
      %{calories: totals.calories + calories, protein: totals.protein + protein}
    end)
  end

  defp add_photo_nutrition(_, days, _timezone), do: days

  defp upload_error(:too_large), do: "Choose an image smaller than 8 MB."
  defp upload_error(:too_many_files), do: "Choose one photo at a time."
  defp upload_error(:not_accepted), do: "Please choose a JPG, PNG, or WebP image."
  defp upload_error(_), do: "This image could not be uploaded. Please try another."
end
