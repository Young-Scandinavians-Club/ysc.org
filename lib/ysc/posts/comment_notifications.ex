defmodule Ysc.Posts.CommentNotifications do
  @moduledoc """
  Emails sent when someone comments on a news article.

  The board hears about every comment. A reply also goes to the member whose
  comment it answers, unless they replied to themselves. Both are best-effort:
  a failure to queue an email is logged and never fails the comment.

  Every job has an idempotency key, so retries never send twice.
  """
  import Ecto.Query

  require Ysc.Logging

  alias Ysc.Accounts.User
  alias Ysc.Posts.{Comment, Post}
  alias Ysc.Repo

  alias YscWeb.Emails.{
    Notifier,
    PostCommentBoardNotification,
    PostCommentReplyNotification
  }

  @reply_author_fields [:id, :email, :first_name, :last_name]

  @doc """
  Queues the emails for `comment`, which `author` just posted on `post`.
  """
  def notify(%Post{} = post, %Comment{} = comment, %User{} = author) do
    safely(comment, fn -> notify_board(post, comment, author) end)
    safely(comment, fn -> notify_replied_to(post, comment, author) end)
    :ok
  end

  defp notify_board(post, comment, author) do
    Notifier.schedule_email(
      Ysc.EmailConfig.board_email(),
      "post_comment_board_notification_#{comment.id}",
      PostCommentBoardNotification.get_subject(post),
      PostCommentBoardNotification.get_template_name(),
      PostCommentBoardNotification.prepare_email_data(post, comment, author),
      "",
      nil,
      reply_to: author.email
    )
  end

  defp notify_replied_to(_post, %Comment{comment_id: nil}, _author), do: :ok

  defp notify_replied_to(
         post,
         %Comment{comment_id: parent_id} = comment,
         author
       ) do
    # `comment_id` comes from the client: only trust a comment on this article.
    case root_comment(parent_id, post.id) do
      %Comment{author: %User{id: id} = root_author} when id != author.id ->
        Notifier.schedule_email(
          root_author.email,
          "post_comment_reply_notification_#{comment.id}",
          PostCommentReplyNotification.get_subject(post),
          PostCommentReplyNotification.get_template_name(),
          PostCommentReplyNotification.prepare_email_data(
            post,
            comment,
            author,
            root_author
          ),
          "",
          root_author.id
        )

      _ ->
        :ok
    end
  end

  # The article page threads replies one level deep, so a reply targets the
  # root comment; if it targets a reply, walk up to that reply's root.
  defp root_comment(comment_id, post_id) do
    case Repo.get_by(Comment, id: comment_id, post_id: post_id) do
      %Comment{comment_id: nil} = root ->
        Repo.preload(root, author: reply_author_query())

      %Comment{comment_id: parent_id} ->
        root_comment(parent_id, post_id)

      nil ->
        nil
    end
  end

  defp reply_author_query do
    from(u in User, select: struct(u, ^@reply_author_fields))
  end

  @doc false
  def ci_query_explain_query do
    reply_author_query()
  end

  defp safely(comment, fun) do
    case fun.() do
      {:error, reason} ->
        Ysc.Logging.warning("Failed to schedule comment notification",
          comment_id: comment.id,
          error: inspect(reason)
        )

      _ ->
        :ok
    end
  rescue
    error ->
      Ysc.Logging.error("Failed to schedule comment notification",
        error: error,
        stacktrace: __STACKTRACE__,
        extra: %{comment_id: comment.id}
      )
  end
end
