defmodule OpenTrackWeb.SettingsLive do
  use OpenTrackWeb, :live_view

  alias OpenTrack.Accounts
  alias OpenTrackWeb.Timezones

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    profile =
      Accounts.get_user_by_id!(user.id,
        actor: user,
        load: [:settings, :avatar, :avatar_url, :followers_count, :following_count]
      )

    {:ok,
     socket
     |> assign(
       page_title: "Settings",
       timezone_options: Timezones.timezone_options(),
       profile: profile
     )
     |> assign_settings_forms(profile.settings)
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
         |> assign_settings_forms(settings)
         |> put_flash(:info, "Targets saved.")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  def handle_event("validate-timezone", %{"preferences" => params}, socket) do
    {:noreply,
     assign(socket, timezone_form: AshPhoenix.Form.validate(socket.assigns.timezone_form, params))}
  end

  def handle_event("save-timezone", %{"preferences" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.timezone_form, params: params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign_settings_forms(settings)
         |> put_flash(:info, "Timezone preferences saved.")}

      {:error, form} ->
        {:noreply, assign(socket, timezone_form: to_form(form))}
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
      Accounts.get_user_by_id!(user.id,
        actor: user,
        load: [:avatar, :avatar_url, :followers_count, :following_count]
      )
    )
  end

  defp assign_settings_forms(socket, settings) do
    user = socket.assigns.current_user

    assign(socket,
      form: settings_form(settings, user, "targets"),
      timezone_form: settings_form(settings, user, "preferences")
    )
  end

  defp settings_form(nil, user, name),
    do: Accounts.form_to_create_settings(actor: user, as: name) |> to_form()

  defp settings_form(settings, user, name),
    do: Accounts.form_to_update_settings(settings, actor: user, as: name) |> to_form()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      app_shell={true}
      active_tab={:settings}
    >
      <section class="account-page">
        <.link
          navigate={~p"/app/profile/#{@current_user.nickname}"}
          class="back-link mb-5"
          id="back-to-profile"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back to profile
        </.link>
        <p class="eyebrow">THE LITTLE DETAILS</p>
        <h1>Make it <span class="highlight">yours.</span></h1>
        <div id="account-profile-card" class="account-card">
          <img
            :if={@profile.avatar}
            id="account-avatar-image"
            src={@profile.avatar_url}
            class="account-avatar account-profile-avatar object-cover"
            width="112"
            height="112"
            alt="Your avatar"
          />
          <span
            :if={!@profile.avatar}
            id="account-avatar-placeholder"
            class="account-avatar account-profile-avatar"
          >
            <.icon name="hero-user" class="size-12" />
          </span>
          <div>
            <h2>{@profile.nickname}</h2>
            <p id="account-email">{@current_user.email}</p>
          </div>
          <div class="account-connections" role="group" aria-label="Profile connections">
            <span id="account-followers">
              <strong class="tabular-nums">{@profile.followers_count}</strong> Followers
            </span>
            <span id="account-following">
              <strong class="tabular-nums">{@profile.following_count}</strong> Following
            </span>
          </div>
        </div>
        <div id="account-preferences">
          <nav class="settings-shortcuts" aria-label="Settings sections">
            <a href="#profile-photo">Profile</a>
            <a href="#targets">Targets</a>
            <a href="#timezone-preferences">Timezone</a>
            <.link navigate={~p"/app/account/security"}>Security</.link>
          </nav>
          <section id="profile-photo" class="targets-editor" aria-labelledby="profile-photo-title">
            <h2 id="profile-photo-title">A familiar face</h2>
            <p>Your photo appears on your public profile. JPG, PNG, or WebP, up to 8 MB.</p>
            <.form
              for={%{}}
              id="avatar-form"
              phx-change="validate-avatar"
              phx-submit="save-avatar"
              class="auth-form"
            >
              <label for={@uploads.avatar.ref}>Profile photo</label>
              <.live_file_input upload={@uploads.avatar} class="avatar-file-input" />
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
              <p :for={_ <- upload_errors(@uploads.avatar)} role="alert">
                Choose one image under 8 MB.
              </p>
              <button type="submit" class="neo-button" phx-disable-with="Saving…">
                Save avatar
              </button>
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
          </section>
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
                Your targets are visible on your public profile and can be updated or cleared at any time.
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
          <section id="timezone-preferences" class="targets-editor" aria-labelledby="timezone-title">
            <div class="flex items-center gap-3">
              <span class="flex size-10 items-center justify-center rounded-lg bg-green-100">
                <.icon name="hero-globe-americas" class="size-6" />
              </span>
              <h2 id="timezone-title">Your day, your timezone</h2>
            </div>
            <p>
              Choose your timezone so daily calorie and protein totals and journal dates follow
              your local day. UTC is the default.
            </p>
            <.form
              for={@timezone_form}
              id="timezone-form"
              phx-change="validate-timezone"
              phx-submit="save-timezone"
              class="auth-form"
            >
              <.input
                field={@timezone_form[:timezone]}
                type="select"
                label="Timezone"
                options={@timezone_options}
              />
              <p class="field-help">
                Choose the region or city matching your local time, such as America/Bogota.
                Daylight saving changes are handled automatically. Changing your timezone also
                regroups past totals; timestamps remain stored in UTC.
              </p>
              <button
                id="save-timezone"
                type="submit"
                class="neo-button auth-submit"
                phx-disable-with="Saving…"
              >
                Save timezone <.icon name="hero-check" class="size-5" />
              </button>
            </.form>
          </section>
          <.link
            navigate={~p"/app/account/security"}
            id="account-security-link"
            class="account-destination mt-7"
          >
            <span class="destination-icon"><.icon name="hero-lock-closed" class="size-6" /></span>
            <span class="destination-copy">
              <strong>Password and security</strong>
              <span>A fresh key to your account.</span>
            </span>
            <.icon name="hero-chevron-right" class="size-5 shrink-0" />
          </.link>
        </div>
        <div class="account-note">
          <.icon name="hero-lock-closed" class="size-6 shrink-0" />
          <div>
            <h2>Your space, at your pace.</h2>
            <p>
              Your food photos, nutrition estimates, and targets appear on your public profile.
              Only you can edit your journal and account settings.
            </p>
          </div>
        </div>
        <.link href={~p"/users/log-out"} method="delete" id="log-out" class="text-link">
          Log out <.icon name="hero-arrow-up-right" class="size-4" />
        </.link>
      </section>
    </Layouts.app>
    """
  end
end
