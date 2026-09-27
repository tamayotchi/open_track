defmodule OpenTrackWeb.AccountLive do
  use OpenTrackWeb, :live_view

  alias OpenTrack.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    settings = Accounts.get_settings_for_user!(user.id, actor: user, not_found_error?: false)

    {:ok,
     socket
     |> assign(page_title: "Your account", form: targets_form(settings, user))
     |> load_profile()
     |> allow_upload(:avatar,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: 8_000_000
     )}
  end

  @impl true
  def handle_event("validate", %{"targets" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save-targets", %{"targets" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(form: targets_form(settings, socket.assigns.current_user))
         |> put_flash(:info, "Targets saved.")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  def handle_event("validate-avatar", _params, socket), do: {:noreply, socket}

  def handle_event("save-avatar", _params, socket) do
    case uploaded_entries(socket, :avatar) do
      {[_], []} ->
        save_avatar(socket)

      _ ->
        {:noreply,
         put_flash(socket, :error, "Choose an image and wait for the upload to finish.")}
    end
  end

  def handle_event("cancel-avatar", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("remove-avatar", _params, socket) do
    user = socket.assigns.current_user

    case Accounts.remove_user_avatar(user, actor: user) do
      {:ok, _} ->
        {:noreply, load_profile(socket) |> put_flash(:info, "Avatar removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove the avatar. Please try again.")}
    end
  end

  defp save_avatar(socket) do
    user = socket.assigns.current_user

    [result] =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        upload = %Plug.Upload{
          path: path,
          filename: Path.basename(entry.client_name),
          content_type: entry.client_type
        }

        {:ok, Accounts.update_user_avatar(user, upload, actor: user)}
      end)

    case result do
      {:ok, _} ->
        {:noreply, load_profile(socket) |> put_flash(:info, "Avatar saved.")}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not save the avatar. Choose a valid JPG, PNG, or WebP under 8 MB and try again."
         )}
    end
  end

  defp load_profile(socket) do
    user = socket.assigns.current_user

    assign(
      socket,
      :profile,
      Accounts.get_user_by_id!(user.id, actor: user, load: [:avatar, :avatar_url])
    )
  end

  defp targets_form(nil, user),
    do: Accounts.form_to_create_settings(actor: user, as: "targets") |> to_form()

  defp targets_form(settings, user),
    do: Accounts.form_to_update_settings(settings, actor: user, as: "targets") |> to_form()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      app_shell={true}
      active_tab={:account}
    >
      <section class="account-page">
        <p class="eyebrow">YOUR OWN LITTLE CORNER</p>
        <h1>Hey, <span class="highlight">you.</span></h1>
        <p class="account-intro">A home for your everyday food moments.</p>
        <div class="account-card">
          <img
            :if={@profile.avatar}
            id="account-avatar-image"
            src={@profile.avatar_url}
            class="account-avatar object-cover"
            alt="Your avatar"
          />
          <span :if={!@profile.avatar} class="account-avatar">
            <.icon name="hero-user" class="size-8" />
          </span>
          <div>
            <h2>Your account</h2>
            <p id="account-email">{@current_user.email}</p>
          </div>
        </div>
        <.form
          for={%{}}
          id="avatar-form"
          phx-change="validate-avatar"
          phx-submit="save-avatar"
          class="auth-form my-6"
        >
          <label for={@uploads.avatar.ref}>Profile photo</label>
          <.live_file_input upload={@uploads.avatar} />
          <div :for={entry <- @uploads.avatar.entries}>
            <.live_img_preview entry={entry} class="size-20 rounded-full object-cover" />
            <button
              type="button"
              phx-click="cancel-avatar"
              phx-value-ref={entry.ref}
              class="text-button"
            >
              Cancel upload
            </button>
            <p :for={_ <- upload_errors(@uploads.avatar, entry)} role="alert">
              Choose a JPG, PNG, or WebP under 8 MB.
            </p>
          </div>
          <p :for={_ <- upload_errors(@uploads.avatar)} role="alert">Choose one image under 8 MB.</p>
          <button type="submit" class="neo-button" phx-disable-with="Saving…">Save avatar</button>
          <button
            :if={@profile.avatar}
            type="button"
            id="remove-avatar"
            phx-click="remove-avatar"
            class="text-button"
          >
            Remove avatar
          </button>
        </.form>
        <section id="targets" class="targets-editor" aria-labelledby="targets-title">
          <h2 id="targets-title">Your targets</h2>
          <p>Set your own goals, or leave them blank. No targets are recommended automatically.</p>
          <.form
            for={@form}
            id="targets-form"
            phx-change="validate"
            phx-submit="save-targets"
            class="auth-form"
          >
            <.input
              field={@form[:target_weight_kg]}
              type="number"
              label="Target weight (kg)"
              min="0.1"
              max="200"
              step="0.1"
              placeholder="Not set"
              phx-debounce="blur"
            />
            <.input
              field={@form[:target_body_fat_percent]}
              type="number"
              label="Target body fat (%)"
              min="0.1"
              max="99.9"
              step="0.1"
              placeholder="Not set"
              phx-debounce="blur"
            />
            <p class="field-help">
              Your targets are private and can be updated or cleared at any time.
            </p>
            <button
              id="save-targets"
              type="submit"
              class="neo-button auth-submit"
              phx-disable-with="Saving…"
            >
              Save targets <.icon name="hero-check" class="size-5" />
            </button>
          </.form>
        </section>
        <div class="account-note">
          <.icon name="hero-lock-closed" class="size-6 shrink-0" />
          <div>
            <h2>Your space, at your pace.</h2>
            <p>
              Your journal, measurements, and preferences are only available to your account.
            </p>
          </div>
        </div>
        <.link navigate={~p"/app/account/settings"} id="account-settings-link" class="neo-button">
          <.icon name="hero-lock-closed" class="size-5" /> Password and security
        </.link>
        <.link href={~p"/users/log-out"} method="delete" id="log-out" class="text-link">
          Log out <.icon name="hero-arrow-up-right" class="size-4" />
        </.link>
      </section>
    </Layouts.app>
    """
  end
end
