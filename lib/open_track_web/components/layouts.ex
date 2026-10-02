defmodule OpenTrackWeb.Layouts do
  @moduledoc "The journal shell, navigation, and connection notices."
  use OpenTrackWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :app_shell, :boolean, default: false
  attr :active_tab, :atom, default: :home
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a href="#main-content" class="skip-link">Skip to content</a>
    <header class={["site-header", @app_shell && "member-header"]}>
      <div class="header-inner">
        <.link
          href={if @current_scope, do: ~p"/app", else: ~p"/"}
          class="brand"
          aria-label="Open Track home"
        >
          <span class="brand-icon"><.icon name="hero-sparkles-solid" class="size-6" /></span>
          open<span class="brand-light">track</span><span class="brand-dot">.</span>
        </.link>
        <span :if={!@app_shell} class="header-label">THE EVERYDAY FOOD JOURNAL</span>
        <%= if @app_shell || @current_scope do %>
          <.link
            navigate={~p"/app/profile/#{@current_scope.actor.nickname}"}
            class="journal-tab"
            id="header-profile"
            aria-current={@active_tab == :account && "page"}
          >
            <.icon name="hero-user-circle" class="size-4" /> Your profile
          </.link>
        <% else %>
          <nav class="header-auth" aria-label="Account navigation">
            <.link navigate={~p"/users/log-in"} id="header-login" class="header-login">Log in</.link>
            <.link navigate={~p"/users/register"} id="header-signup" class="journal-tab">
              Sign up <.icon name="hero-arrow-up-right" class="size-4" />
            </.link>
          </nav>
        <% end %>
      </div>
    </header>
    <main id="main-content" class={["app-main", @app_shell && "member-main"]}>
      {render_slot(@inner_block)}
    </main>
    <nav :if={@app_shell} id="bottom-nav" class="bottom-nav" aria-label="App navigation">
      <div class="bottom-nav-inner">
        <.link
          navigate={~p"/app"}
          id="nav-home"
          class={["bottom-tab", @active_tab == :home && "active"]}
          aria-current={@active_tab == :home && "page"}
        >
          <.icon name="hero-home" class="size-6" /><span>Home</span>
        </.link>
        <.link
          navigate={~p"/app/add"}
          id="nav-add-food"
          class="bottom-add"
          aria-label="Add food"
          aria-current={@active_tab == :add && "page"}
        >
          <span class="bottom-plus"><.icon name="hero-plus" class="size-8" /></span><span>Add food</span>
        </.link>
        <.link
          navigate={~p"/app/profile/#{@current_scope.actor.nickname}"}
          id="nav-account"
          class={["bottom-tab", @active_tab in [:account, :settings] && "active"]}
          aria-current={if @active_tab == :account, do: "page"}
          data-active={to_string(@active_tab in [:account, :settings])}
        >
          <.icon name="hero-user-circle" class="size-6" /><span>Account</span>
        </.link>
      </div>
    </nav>
    <div class={@app_shell && "member-flashes"}><.flash_group flash={@flash} /></div>
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title="Connection lost"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Trying to reconnect. Please wait a moment.
      </.flash>
      <.flash
        id="server-error"
        kind={:error}
        title="Reconnecting"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Please wait before trying again.
      </.flash>
    </div>
    """
  end
end
