defmodule OpenTrackWeb.HomeLive do
  use OpenTrackWeb, :live_view

  alias OpenTrack.{Accounts, Food}
  alias OpenTrackWeb.{FoodComponents, Timezones}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    settings =
      Accounts.get_user_by_id!(user.id, actor: user, load: :public_settings).public_settings

    {:ok,
     socket
     |> assign(page_title: "Home", timezone: settings.timezone || Timezones.utc())
     |> load_feed()}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    {:noreply,
     if(socket.assigns.more?, do: load_feed(socket, socket.assigns.after), else: socket)}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_feed(socket)}
  end

  defp load_feed(socket, after_key \\ nil) do
    page_options = [limit: 12]

    page_options =
      if after_key, do: Keyword.put(page_options, :after, after_key), else: page_options

    case Food.list_followed_users_photos(
           actor: socket.assigns.current_user,
           page: page_options,
           load: [:image_url, user: [:avatar_url]]
         ) do
      {:ok, page} ->
        socket
        |> assign(
          more?: page.more?,
          after: if(page.results != [], do: List.last(page.results).__metadata__.keyset),
          feed_error?: false
        )
        |> stream(:posts, page.results, reset: is_nil(after_key))

      {:error, _error} ->
        socket
        |> assign(feed_error?: true)
        |> assign_new(:more?, fn -> false end)
        |> assign_new(:after, fn -> nil end)
        |> stream(:posts, [])
        |> put_flash(:error, "Could not load your feed. Please try again.")
    end
  end
end
