---
title: Posts & news articles
summary: Post lifecycle, editor and autosave, URL slugs, featured images, preview, publishing, pinning, deleting/restoring, comments, and list filters.
---

# Posts & news articles

Admin pages: `/admin/posts` (list), `/admin/posts/new` (editor), `/admin/posts/:id` (editor), `/admin/posts/:id/preview` (preview). Public pages: `/news` (listing) and `/posts/:slug`.

## Lifecycle and states

- A post is in one of three states: **Draft**, **Published**, or **Deleted** (soft-deleted).
- New posts start as a Draft with the default title "New Untitled Post".
- **Publish** sets the published timestamp (UTC) and makes the post public immediately. There is no scheduled publishing for posts — keep it as a draft until the day it should go live.
- On first publish, the author's board position is snapshotted onto the post, so the byline shows the position they held at publish time.
- Publishing invalidates the public content cache, so the article appears on /news right away.
- **Delete** is a soft delete: it marks the post Deleted, clears the published date, and clears any pin. **Restore** brings a deleted post back as a Draft (publish date and pin stay cleared).

## Editor and autosave

- Work auto-saves: the body autosaves 2 seconds after you stop typing; the title field debounces at 500 ms. A "Saving..." indicator with a spinning icon shows while a save is in flight.
- The first auto-save creates the post and the URL changes from /admin/posts/new to the post's permanent editor URL.
- The body uses a rich-text (Trix) editor with bold, italic, headings, quotes, links, and lists. The placeholder text is "Write something delightful and nice...".
- Body HTML is sanitized on save (basic HTML scrubber), so pasted scripts/styles are stripped.
- Inline images are inserted via the editor toolbar, which opens the shared media library picker.

## Title and URL slug rules

- Title is limited to 150 characters.
- The public URL slug is generated from the title: lowercased, spaces become hyphens, anything outside a–z/0–9/hyphen is stripped. A blank title produces the slug "new-untitled-post".
- If a slug is already taken, a numeric suffix is appended (e.g. "my-post-2").
- The slug auto-syncs with the title while the post is new; once the slug is manually edited, it stops following the title. Manual slugs are validated for uniqueness on save.
- Changing the slug after publishing breaks links already shared.

## Featured image (required to publish)

- A featured image is **required** before publishing. It is set in the **Post Settings** modal (opened from the ⋮ menu in the editor).
- If you click **Publish** without one, the Post Settings modal opens instead; after you pick an image, publishing completes automatically (a "pending publish" flow). Success toast: "Post published!".
- The featured image appears on the /news listing cards, in link previews, and in newsletters that include the post.
- Post Settings can only be opened once the post has been saved at least once.

## Preview

- The **Preview** button opens a full-screen preview with **Phone**, **Tablet**, and **Desktop** device mockups (the public page rendered in an iframe).
- Staff (admins and volunteers) can also open the public URL of a draft directly — it renders with an amber "Staff preview" banner. Regular members cannot view drafts.

## Pinning (featured post)

- Pinning makes a post the large featured article at the top of /news. Only **one** post can be pinned at a time, and only **published** posts can be pinned.
- Pin/unpin from the list's ⋮ menu: **Pin post** / **Unpin post**. A yellow star icon marks the pinned post.
- Pinning a new post automatically unpins the previous one.
- Deleting or restoring a post clears its pin.

## Deleting and restoring

- From the **list**, only Drafts can be deleted (confirmation: "Delete this draft? It will be marked as deleted."). Attempting on a published post shows "Only draft posts can be deleted from here."
- Published posts are deleted from inside the **editor** (⋮ menu → Delete Post).
- Deleted posts show a green **Restore** button in the editor; restore returns them to Draft.
- Deleted posts are excluded from the default list view.

## Comments

- Logged-in members can comment on published articles; comments support threaded replies.
- The posts list shows a comment count per post (chat bubble icon).
- The admin dashboard's "Recent discussions" feed shows the latest 5 comments on published posts.
- Comment moderation: admins can edit/delete any comment; authors can edit/delete their own.

## List, search, and filters

- The list page has a **New Post** button and a search box ("Search by post title...") that also matches preview text and author name.
- Filters: **State** (Published / Draft), **Author**, and **Date Posted** range (From / To).
- Default sort is creation date, newest first; 50 posts per page by default.
- Row actions: **View live** (published only), **Edit**, **Pin post**/**Unpin post**, **Delete** (drafts only).

## Permissions

- Both volunteers and admins can create, edit, and publish posts.
