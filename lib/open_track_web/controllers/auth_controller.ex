defmodule OpenTrackWeb.AuthController do
  @moduledoc "Password registration, login forms, and browser sessions over HTTP."
  use OpenTrackWeb, :controller

  alias OpenTrack.Accounts
  alias OpenTrackWeb.UserAuth

  plug :redirect_authenticated
       when action in [:new_session, :new_registration, :sign_in, :register]

  def new_session(conn, _params), do: render_form(conn, :login, auth_form(:login))
  def new_registration(conn, _params), do: render_form(conn, :register, auth_form(:register))

  def sign_in(conn, params), do: submit_form(conn, :login, params)
  def register(conn, params), do: submit_form(conn, :register, params)

  def sign_out(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> redirect(to: ~p"/users/log-in")
  end

  defp redirect_authenticated(conn, _opts) do
    if conn.assigns.current_user do
      conn |> redirect(to: ~p"/app") |> halt()
    else
      conn
    end
  end

  defp submit_form(conn, mode, %{"user" => params}) when is_map(params) do
    # Credentials are scalar form fields, not nested structures or auth context.
    fields =
      if mode == :register,
        do: ~w(nickname email password password_confirmation),
        else: ~w(email password)

    params =
      Map.new(fields, fn field ->
        value = Map.get(params, field)
        {field, if(is_binary(value), do: value)}
      end)

    case AshPhoenix.Form.submit(auth_form(mode), params: params, read_one?: true) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)
        |> redirect(to: ~p"/app")

      {:error, form} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render_form(mode, form)
    end
  end

  defp submit_form(conn, mode, _params), do: submit_form(conn, mode, %{"user" => %{}})

  defp render_form(conn, mode, form) do
    render(conn, :auth,
      mode: mode,
      page_title: if(mode == :register, do: "Sign up", else: "Log in"),
      current_scope: nil,
      form: Phoenix.Component.to_form(form)
    )
  end

  defp auth_form(mode) do
    opts = [
      as: "user",
      context: UserAuth.password_context(),
      transform_errors: &form_error/2
    ]

    case mode do
      :register -> Accounts.form_to_register_user(opts)
      :login -> Accounts.form_to_sign_in(opts)
    end
  end

  defp form_error(_source, %AshAuthentication.Errors.AuthenticationFailed{}) do
    {:password, "Email or password is incorrect", []}
  end

  defp form_error(_source, error), do: error
end
