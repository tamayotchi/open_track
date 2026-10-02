defmodule OpenTrackWeb.AddFoodLive do
  use OpenTrackWeb, :live_view

  alias OpenTrack.Food

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Add food",
       form:
         Food.form_to_create_food_photo(actor: socket.assigns.current_user, as: "photo")
         |> to_form()
     )
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: 8_000_000
     )}
  end

  @impl true
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

  def handle_event(_event, _params, socket), do: {:noreply, socket}

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
         |> put_flash(:info, "Photo saved.")
         |> push_navigate(to: ~p"/app/profile/#{user.nickname}")}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not save this photo. Choose a valid JPG, PNG, or WebP under 8 MB and try again."
         )}
    end
  end

  defp upload_error(:too_large), do: "Choose an image smaller than 8 MB."
  defp upload_error(:too_many_files), do: "Choose one photo at a time."
  defp upload_error(:not_accepted), do: "Please choose a JPG, PNG, or WebP image."
  defp upload_error(_), do: "This image could not be uploaded. Please try another."
end
