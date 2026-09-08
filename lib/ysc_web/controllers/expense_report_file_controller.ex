defmodule YscWeb.ExpenseReportFileController do
  # Register @sobelow_skip so the Elixir compiler does not warn about the attribute
  # being unused (Sobelow consumes it from the source AST, not via Elixir reflection).
  Module.register_attribute(__MODULE__, :sobelow_skip, accumulate: true)

  use YscWeb, :controller

  alias Ysc.ExpenseReports
  alias Ysc.S3Config
  require Ysc.Logging

  @inline_content_types ~w(
    application/pdf
    image/jpeg
    image/png
    image/webp
    image/gif
  )

  @doc """
  Generates a presigned URL for viewing an expense report file (receipt or proof document).
  Only the owner of the expense report or an admin can access the file.
  """
  def show(conn, %{"encoded_path" => encoded_path}) do
    Ysc.Logging.debug("Expense report file request",
      request_path: conn.request_path
    )

    with_current_user(conn, fn user ->
      with_authorized_file(conn, user, encoded_path, fn s3_path,
                                                        expense_report ->
        generate_and_redirect_to_presigned_url(
          conn,
          user,
          s3_path,
          expense_report
        )
      end)
    end)
  end

  @doc """
  Streams the file inline with a detected Content-Type so images and PDFs can
  be rendered in the admin review modal (`<img>` / `<iframe>`).
  """
  def preview(conn, %{"encoded_path" => encoded_path}) do
    Ysc.Logging.debug("Expense report file preview request",
      request_path: conn.request_path
    )

    with_current_user(conn, fn user ->
      with_authorized_file(conn, user, encoded_path, fn s3_path,
                                                        expense_report ->
        serve_inline_file(conn, user, s3_path, expense_report)
      end)
    end)
  end

  defp with_current_user(conn, on_user) do
    user = conn.assigns[:current_user]

    if is_nil(user) do
      Ysc.Logging.debug("No current_user in ExpenseReportFileController")

      YscWeb.ErrorHTML.render_page(conn, :"403")
    else
      on_user.(user)
    end
  end

  defp with_authorized_file(conn, user, encoded_path, on_ok) do
    case Base.url_decode64(encoded_path, padding: false) do
      {:ok, s3_path} ->
        case ExpenseReports.can_access_file?(user, s3_path) do
          {:ok, expense_report} ->
            on_ok.(s3_path, expense_report)

          {:error, :not_found} ->
            Ysc.Logging.warning(
              "User attempted to access file not found in any expense report",
              user_id: user.id,
              s3_path: s3_path
            )

            YscWeb.ErrorHTML.render_page(conn, :"404")

          {:error, :unauthorized} ->
            Ysc.Logging.warning(
              "User attempted to access file from expense report they don't own",
              user_id: user.id,
              s3_path: s3_path
            )

            YscWeb.ErrorHTML.render_page(conn, :"403")
        end

      :error ->
        Ysc.Logging.warning(
          "Invalid base64 encoded path in expense report file request",
          user_id: user.id
        )

        YscWeb.ErrorHTML.render_page(conn, :"400")
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

        YscWeb.ErrorHTML.render_page(conn, :"500")
    end
  end

  # send_resp delivers receipt bytes with a non-HTML content type (PDF/image)
  # and an explicit Content-Disposition. Sobelow flags send_resp binaries as XSS.
  @sobelow_skip ["XSS.SendResp"]
  defp serve_inline_file(conn, user, s3_path, expense_report) do
    case ExpenseReports.fetch_file(s3_path) do
      {:ok, binary} when is_binary(binary) ->
        content_type = receipt_content_type(s3_path, binary)
        filename = sanitize_download_filename(s3_path)

        disposition =
          if content_type in @inline_content_types do
            "inline"
          else
            "attachment"
          end

        Ysc.Logging.debug("Streaming expense report file preview",
          user_id: user.id,
          s3_path: s3_path,
          expense_report_id:
            if(expense_report, do: expense_report.id, else: "unsaved"),
          content_type: content_type
        )

        conn
        |> put_resp_header("content-type", content_type)
        |> put_resp_header(
          "content-disposition",
          ~s[#{disposition}; filename="#{filename}"]
        )
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(200, binary)

      {:error, reason} ->
        Ysc.Logging.error(
          "Failed to fetch expense report file for preview",
          user_id: user.id,
          s3_path: s3_path,
          error: inspect(reason)
        )

        YscWeb.ErrorHTML.render_page(conn, :"500")
    end
  end

  defp receipt_content_type(s3_path, binary) do
    from_ext = MIME.from_path(s3_path)

    if from_ext == "application/octet-stream" do
      content_type_from_magic(binary) || "application/octet-stream"
    else
      from_ext
    end
  end

  defp content_type_from_magic(<<"%PDF", _::binary>>), do: "application/pdf"

  defp content_type_from_magic(<<0xFF, 0xD8, 0xFF, _::binary>>),
    do: "image/jpeg"

  defp content_type_from_magic(
         <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>
       ),
       do: "image/png"

  defp content_type_from_magic(
         <<"RIFF", _::binary-size(4), "WEBP", _::binary>>
       ),
       do: "image/webp"

  defp content_type_from_magic(_), do: nil

  defp sanitize_download_filename(s3_path) do
    s3_path
    |> Path.basename()
    |> String.replace(~r/[^a-zA-Z0-9._-]/, "_")
    |> case do
      "" -> "receipt"
      name -> name
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
