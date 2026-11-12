defmodule Ysc.Posts.PostTest do
  use Ysc.DataCase, async: true

  alias Ysc.Posts.Post

  describe "public_page_fields/0" do
    test "is an explicit subset of persisted columns used on the public page" do
      fields = Post.public_page_fields()
      schema_fields = Post.__schema__(:fields)

      assert fields -- schema_fields == []
      assert :rendered_body in fields
      assert :preview_text in fields
      assert :comment_count in fields
      assert :board_position_at_publish in fields
      assert :state in fields
      assert :url_name in fields
      assert :inserted_at in fields
      refute :raw_body in fields
      refute :deleted_on in fields
      refute :featured_post in fields
      refute :updated_by_id in fields
      refute :updated_at in fields
    end
  end
end
