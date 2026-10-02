defmodule OpenTrackWeb.ProfileLive do
  use OpenTrackWeb, :live_view

  alias OpenTrack.{Accounts, Food}
  alias OpenTrackWeb.{FoodComponents, NutritionChart, NutritionComponents, Timezones}

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"nickname" => nickname}, _uri, socket) do
    profile =
      Accounts.get_public_profile!(nickname,
        not_found_error?: false,
        load: [:avatar_url, :followers_count, :following_count]
      )

    {:noreply, load_profile(socket, profile)}
  end

  @impl true
  def handle_event(_event, _params, %{assigns: %{profile: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event(event, _params, socket) when event in ["follow", "unfollow"] do
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

  def handle_event("set-view", %{"mode" => mode}, socket) when mode in ["cards", "table"] do
    {:noreply, assign(socket, view_mode: if(mode == "cards", do: :cards, else: :table))}
  end

  def handle_event("load-more", _, socket) do
    {:noreply,
     if(socket.assigns.more?, do: load_photos(socket, socket.assigns.after), else: socket)}
  end

  def handle_event("delete-photo", %{"id" => id}, %{assigns: %{profile_owner?: true}} = socket) do
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

  # Visitors cannot delete photos, and uploads/settings belong to separate views.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp load_profile(socket, nil) do
    socket
    |> assign(
      profile: nil,
      profile_owner?: false,
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

  defp load_profile(socket, profile) do
    settings = profile.public_settings
    timezone = settings.timezone || Timezones.utc()

    socket
    |> assign(
      profile: profile,
      profile_owner?:
        not is_nil(socket.assigns.current_user) && socket.assigns.current_user.id == profile.id,
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

  defp load_photos(socket, after_key \\ nil) do
    pagination = [limit: 24, count: true]
    pagination = if after_key, do: Keyword.put(pagination, :after, after_key), else: pagination

    page =
      Food.list_food_photos!(socket.assigns.profile.id,
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
      Food.nutrition_chart_data!(socket.assigns.profile.id, from, until)
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
end
