defmodule YscWeb.Api.FallbackController do
  @moduledoc """
  Fallback controller for mobile API error handling.
  """
  use YscWeb, :controller

  def call(conn, {:error, :missing_property}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "property is required. Use 'tahoe' or 'clear_lake'"})
  end

  def call(conn, {:error, :invalid_property}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid property. Use 'tahoe' or 'clear_lake'"})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not found"})
  end

  def call(conn, {:error, {:invalid_date, key}}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "invalid date format for '#{key}'. Use ISO 8601 (YYYY-MM-DD)"
    })
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors = YscWeb.FormHelpers.changeset_errors(changeset)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation failed", errors: errors})
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: reason})
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "an unexpected error occurred"})
  end
end
