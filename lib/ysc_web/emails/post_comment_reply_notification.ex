defmodule YscWeb.Emails.PostCommentReplyNotification do
  @moduledoc """
  Email template telling a member that someone replied to their comment on a
  news article, with a link to the reply.
  """
  use MjmlEEx,
    mjml_template: "templates/post_comment_reply_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Accounts.{User, UserDisplay}
  alias Ysc.Posts.{Comment, Post}
  alias YscWeb.Emails.PostCommentBoardNotification

  def get_template_name, do: "post_comment_reply_notification"

  def get_subject(%Post{title: title}),
    do: "New reply to your comment on \"#{title}\" - YSC"

  def prepare_email_data(
        %Post{} = post,
        %Comment{} = reply,
        %User{} = replier,
        %User{} = parent_author
      ) do
    %{
      first_name: parent_author.first_name,
      post_title: post.title,
      replier_name: UserDisplay.full_name(replier),
      reply_text: reply.text,
      comment_url: PostCommentBoardNotification.comment_url(post, reply)
    }
  end
end
