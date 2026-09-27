defmodule OpenTrackWeb.SecurityLive do
  use OpenTrackWeb, :live_view

  alias OpenTrack.Accounts

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    {:ok, assign(socket, page_title: "Password and security", form: password_form(actor))}
  end

  @impl true
  def handle_event("save-password", %{"password" => params}, socket) do
    actor = socket.assigns.current_user
    # Another tab may have changed the password since this page mounted.
    user = Accounts.get_user_by_id!(actor.id, actor: actor)

    case AshPhoenix.Form.submit(password_form(user), params: params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(
           current_user: user,
           current_scope: %{socket.assigns.current_scope | actor: user},
           form: password_form(user)
         )
         |> put_flash(:info, "Password updated.")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp password_form(user) do
    user
    |> Accounts.form_to_change_user_password(
      actor: user,
      as: "password",
      transform_errors: &form_error/2
    )
    |> to_form()
  end

  defp form_error(_source, %AshAuthentication.Errors.AuthenticationFailed{}) do
    {:current_password, "Current password is incorrect", []}
  end

  defp form_error(_source, error), do: error

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      app_shell={true}
      active_tab={:account}
    >
      <section class="settings-page">
        <.link navigate={~p"/app/account"} class="back-link" id="back-to-account">
          <.icon name="hero-arrow-left" class="size-4" /> Back to account
        </.link>
        <header class="settings-heading">
          <div>
            <p class="eyebrow">YOUR ACCOUNT, YOUR CONTROL</p>
            <h1>A little <span class="highlight">peace of mind.</span></h1>
            <p>Password and security for your own little corner.</p>
          </div>
          <span class="settings-emblem"><.icon name="hero-lock-closed" class="size-9" /></span>
        </header>
        <div class="settings-grid">
          <section class="settings-card" aria-labelledby="password-title">
            <header class="settings-card-heading">
              <span class="settings-icon"><.icon name="hero-key" class="size-5" /></span>
              <div>
                <h2 id="password-title">Change password</h2>
                <p>A fresh key to your journal.</p>
              </div>
            </header>
            <.form
              for={@form}
              id="password-form"
              phx-submit="save-password"
              class="auth-form settings-password-form"
            >
              <fieldset class="grid gap-5" aria-describedby="password-help">
                <.input
                  field={@form[:current_password]}
                  type="password"
                  label="Current password"
                  value={nil}
                  autocomplete="current-password"
                />
                <.input
                  field={@form[:password]}
                  type="password"
                  label="New password"
                  value={nil}
                  autocomplete="new-password"
                />
                <p class="field-help">Choose a password with at least 8 characters.</p>
                <.input
                  field={@form[:password_confirmation]}
                  type="password"
                  label="Confirm new password"
                  value={nil}
                  autocomplete="new-password"
                />
                <button
                  id="save-password"
                  type="submit"
                  class="neo-button auth-submit"
                  phx-disable-with="Updating…"
                >
                  Update password <.icon name="hero-check" class="size-5" />
                </button>
              </fieldset>
              <p id="password-help" class="settings-notice">
                <.icon name="hero-information-circle" class="size-5 shrink-0" />
                Changing your password keeps you signed in on your devices.
              </p>
            </.form>
          </section>
          <aside class="settings-card settings-identity">
            <p class="eyebrow">YOUR LITTLE CORNER</p>
            <span class="account-avatar"><.icon name="hero-user" class="size-7" /></span>
            <h2>Your account</h2>
            <p>{@current_user.email}</p>
            <p class="settings-small-print">
              Use a unique password to keep your private journal safe.
            </p>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
