defmodule YscWeb.ExpenseReportFileController do
  use YscWeb, :controller

  alias Ysc.ExpenseReports
  alias Ysc.S3Config
  require Ysc.Logging

  @doc """
  Generates a presigned URL for viewing an expense report file (receipt or proof document).
  Only the owner of the expense report or an admin can access the file.
  """
  def show(conn, %{"encoded_path" => encoded_path}) do
    Ysc.Logging.debug("Expense report file request",
      request_path: conn.request_path
    )

    user = conn.assigns[:current_user]

    if is_nil(user) do
      Ysc.Logging.debug("No current_user in ExpenseReportFileController")

      conn
      |> put_status(:forbidden)
      |> put_view(html: YscWeb.ErrorHTML)
      |> render(:"403")
    else
      handle_expense_report_file_request(conn, user, encoded_path)
    end
  end

  defp handle_expense_report_file_request(conn, user, encoded_path) do
    case Base.url_decode64(encoded_path, padding: false) do
      {:ok, s3_path} ->
        handle_decoded_path(conn, user, s3_path)

      :error ->
        Ysc.Logging.warning(
          "Invalid base64 encoded path in expense report file request",
          user_id: user.id
        )

        conn
        |> put_status(:bad_request)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"400")
    end
  end

  defp handle_decoded_path(conn, user, s3_path) do
    case ExpenseReports.can_access_file?(user, s3_path) do
      {:ok, expense_report} ->
        generate_and_redirect_to_presigned_url(
          conn,
          user,
          s3_path,
          expense_report
        )

      {:error, :not_found} ->
        Ysc.Logging.warning(
          "User attempted to access file not found in any expense report",
          user_id: user.id,
          s3_path: s3_path
        )

        conn
        |> put_status(:not_found)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"404")

      {:error, :unauthorized} ->
        Ysc.Logging.warning(
          "User attempted to access file from expense report they don't own",
          user_id: user.id,
          s3_path: s3_path
        )

        conn
        |> put_status(:forbidden)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"403")
    end
  end

  defp generate_and_redirect_to_presigned_url(
         conn,
         user,
         s3_path,
         expense_report
       ) do
    expires_in = 3600
    normalized_path = normalize_s3_path_for_presigned_url(s3_path)

    {config, method, bucket_or_host, object_key, presign_opts} =
      S3Config.expense_report_file_presigned_url_args(
        normalized_path,
        expires_in
      )

    case ExAws.S3.presigned_url(
           config,
           method,
           bucket_or_host,
           object_key,
           presign_opts
         ) do
      {:ok, presigned_url} ->
        Ysc.Logging.debug("Generated presigned URL for expense report file",
          user_id: user.id,
          s3_path: normalized_path,
          expense_report_id:
            if(expense_report, do: expense_report.id, else: "unsaved"),
          expires_in: expires_in
        )

        redirect(conn, external: presigned_url)

      {:error, reason} ->
        Ysc.Logging.error(
          "Failed to generate presigned URL for expense report file",
          user_id: user.id,
          s3_path: s3_path,
          error: inspect(reason)
        )

        conn
        |> put_status(:internal_server_error)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"500")
    end
  end

  # Normalizes S3 path for presigned URL generation
  # Removes bucket name prefix if present, as ExAws expects just the key
  defp normalize_s3_path_for_presigned_url(s3_path) do
    bucket_name = S3Config.expense_reports_bucket_name()
    prefix = "#{bucket_name}/"

    if String.starts_with?(s3_path, prefix) do
      String.replace_prefix(s3_path, prefix, "")
    else
      s3_path
    end
  end
end
