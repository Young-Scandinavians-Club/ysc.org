import EctoEnum

defenum(PostState, ["draft", "published", "deleted"])

defenum(PostEventType, [
  "post_deleted",
  "post_created",
  "post_title_updated",
  "post_body_updated",
  "post_featured_image_updated",
  "post_featured_post_updated",
  "post_published",
  "post_unpublished"
])
