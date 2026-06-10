---
title: Media library (images)
summary: Uploading images (drag-drop, batches, accepted formats), automatic optimization to WebP, thumbnails, search and the year timeline, editing title/alt text, copy URL actions, and permissions.
---

# Media library

Admin pages: `/admin/media` (gallery), `/admin/media/upload` (upload flow). One shared library powers the whole site: post featured/inline images, event covers, and newsletter photos all come from here.

## Uploading

- Two paths: the **Upload new images** modal, or **drag and drop files anywhere onto the gallery** ("Drop images to upload"), which uploads automatically on drop.
- Accepted formats: .jpg, .jpeg, .png, .gif, .webp.
- Up to **10 files per batch**. Unaccepted file types show "You have selected an unacceptable file type".
- Files upload directly to cloud storage (S3) and are then processed.
- Upload originals at full resolution — optimization is automatic (see below), so there's no need to pre-resize.
- Editors (posts, events, newsletters) open pickers into this same library and also accept direct uploads.

## Automatic optimization

- Each image is processed into:
  - an **Optimized** version — max 1920×1920 px, quality 85, converted to WebP;
  - a **Thumbnail** — 500 px on the longest side;
  - the **Raw** original is kept too.
- A blur placeholder (BlurHash) is generated for smooth loading on the public site.
- The image's processing state is shown (e.g. "Completed"); large originals can take a moment before the thumbnail appears.

## Finding images

- Search by **filename, title, or alt text** ("Search by filename, title, or alt text...").
- A **year timeline scrubber** along the gallery edge jumps to images from a given year.
- Layout toggle includes a masonry grid view.

## Editing image details

- Each image has an edit modal with **Title** and **Alt Text** fields (button "Update Image"). Good alt text helps accessibility and search.
- Copy actions per image: **Copy URL**, **Copy Markdown**, **Copy HTML**.

## Permissions

- The media pages are visible to volunteers and admins; image **read** is open to all staff.
- The authorization policy restricts image create/update/delete to **admins** — volunteers may hit authorization errors on uploads or edits depending on where enforcement applies. If a volunteer cannot upload, an admin can do it or adjust roles.

## Tips

- Landscape photos with the subject near the center crop best across cards, covers, and emails.
- Blurry on the page usually means a tiny original — upload a higher-resolution version.
- After a club event, batch-upload the best 10–20 shots so they're ready for the recap post and newsletter.
