defmodule YscWeb.Emails.PostCommentBoardNotification do
  @moduledoc """
  Email template for the board notification about a new news article comment.

  Tells the board a member commented on an article and links straight to the
  comment.
  """
  use MjmlEEx,
    mjml_template: "templates/post_comment_board_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [absolute_url: 1]

  alias Ysc.Accounts.{User, UserDisplay}
  alias Ysc.Posts.{Comment, Post}

  def get_template_name, do: "post_comment_board_notification"

  def get_subject(%Post{title: title}), do: "New comment on \"#{title}\" - YSC"

  @doc """
  Absolute link to `comment` on its article. The fragment matches the DOM id
  the article page gives each comment, so the browser scrolls to it.
  """
  def comment_url(%Post{url_name: url_name}, %Comment{id: comment_id}),
    do: absolute_url("/posts/#{url_name}#comments-#{comment_id}")

  def prepare_email_data(%Post{} = post, %Comment{} = comment, %User{} = author) do
    %{
      post_title: post.title,
      author_name: UserDisplay.full_name(author),
      author_email: author.email,
      comment_text: comment.text,
      reply: not is_nil(comment.comment_id),
      comment_url: comment_url(post, comment),
      submitted_at: format_submitted_at(comment.inserted_at)
    }
  end

  defp format_submitted_at(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> Calendar.strftime("%B %d, %Y at %I:%M %p %Z")
  end
end
