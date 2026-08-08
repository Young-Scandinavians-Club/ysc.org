import Trix from "../vendor/trix";

function emitEditorUpdateEvent(source, el) {
  if (!el || !el.isConnected) return;
  try {
    const view = source.__view();
    if (!view || !view.isConnected()) return;
  } catch (_) {
    return;
  }
  source.pushEvent("editor-update", { field: el.name, value: el.value });
}

function uploadFileAttachment(attachment, postID, editorEl) {
  uploadFile(attachment.file, postID, setProgress, setAttributes, setError);

  function setProgress(progress) {
    attachment.setUploadProgress(progress);
  }

  function setAttributes(attributes) {
    attachment.setAttributes(attributes);
  }

  function setError(message) {
    if (editorEl && editorEl.editor) {
      editorEl.editor.removeAttachment(attachment);
    }
    alert(`Upload failed: ${message}`);
  }
}

function uploadFile(file, postID, progressCallback, successCallback, errorCallback) {
  const formData = new FormData();
  formData.append("file", file);
  if (postID) {
    formData.append("post_id", postID);
  }
  const csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");
  const xhr = new XMLHttpRequest();

  xhr.open("POST", "/admin/trix-uploads", true);
  xhr.setRequestHeader("X-CSRF-Token", csrfToken);

  xhr.upload.addEventListener("progress", function (event) {
    if (event.lengthComputable) {
      const progress = Math.round((event.loaded / event.total) * 100);
      progressCallback(progress);
    }
  });

  xhr.addEventListener("load", function (_event) {
    if (xhr.status === 201) {
      try {
        const data = JSON.parse(xhr.responseText);
        const url = data.url;
        const attributes = {
          url,
          href: `${url}?content-disposition=attachment`,
          filename: data.filename,
          contentType: data.content_type,
        };
        successCallback(attributes);
      } catch (_e) {
        // Fallback for plain-text URL response (no filename/contentType available)
        const url = xhr.responseText;
        const attributes = { url, href: `${url}?content-disposition=attachment` };
        successCallback(attributes);
      }
    } else {
      let message = "An unexpected error occurred.";
      try {
        const data = JSON.parse(xhr.responseText);
        if (data.error) message = data.error;
      } catch (_e) {
        // keep default message
      }
      errorCallback(message);
    }
  });

  xhr.send(formData);
}

function addCustomToolbarButtons(editorEl, hook) {
  const hookEl = hook.el;
  const toolbarId = editorEl.getAttribute("toolbar");
  const toolbar = document.getElementById(toolbarId);
  if (!toolbar) return;

  const fileTools = toolbar.querySelector(
    "[data-trix-button-group='file-tools']",
  );
  if (!fileTools) return;

  if (!fileTools.querySelector(".trix-button--icon-library")) {
    const libraryBtn = document.createElement("button");
    libraryBtn.type = "button";
    libraryBtn.className =
      "trix-button trix-button--icon trix-button--icon-library";
    libraryBtn.title = "Insert from library";
    libraryBtn.tabIndex = -1;
    libraryBtn.textContent = "Library";
    libraryBtn.addEventListener("mousedown", (e) => e.preventDefault());
    libraryBtn.addEventListener("click", (e) => {
      e.preventDefault();
      const trigger = document.querySelector(
        `[data-trix-library-trigger="${hookEl.id}"]`,
      );
      if (trigger) trigger.click();
    });
    fileTools.appendChild(libraryBtn);
  }

  if (!fileTools.querySelector(".trix-button--icon-horizontal-rule")) {
    const hrBtn = document.createElement("button");
    hrBtn.type = "button";
    hrBtn.className =
      "trix-button trix-button--icon trix-button--icon-horizontal-rule";
    hrBtn.title = "Divider";
    hrBtn.tabIndex = -1;
    hrBtn.textContent = "Divider";
    hrBtn.addEventListener("mousedown", (e) => e.preventDefault());
    hrBtn.addEventListener("click", (e) => {
      e.preventDefault();
      const attachment = new Trix.Attachment({
        content: "<hr>",
        contentType: "application/vnd.trix.horizontal-rule.html",
      });
      editorEl.editor.insertAttachment(attachment);
    });
    fileTools.appendChild(hrBtn);
  }

  if (
    hookEl.getAttribute("data-newsletter-notices") === "true" &&
    !fileTools.querySelector(".trix-button--icon-saved-notice")
  ) {
    const noticeBtn = document.createElement("button");
    noticeBtn.type = "button";
    noticeBtn.className =
      "trix-button trix-button--icon trix-button--icon-saved-notice";
    noticeBtn.title = "Insert saved notice";
    noticeBtn.tabIndex = -1;
    noticeBtn.textContent = "Notice";
    noticeBtn.addEventListener("mousedown", (e) => e.preventDefault());
    noticeBtn.addEventListener("click", (e) => {
      e.preventDefault();
      const trigger = document.querySelector(
        `[data-trix-notices-trigger="${hookEl.id}"]`,
      );
      if (trigger) trigger.click();
    });
    fileTools.appendChild(noticeBtn);
  }

  if (
    hookEl.getAttribute("data-newsletter-notices") === "true" &&
    !fileTools.querySelector(".trix-button--icon-save-notice")
  ) {
    const saveNoticeBtn = document.createElement("button");
    saveNoticeBtn.type = "button";
    saveNoticeBtn.className =
      "trix-button trix-button--icon trix-button--icon-save-notice";
    saveNoticeBtn.title = "Save selection as notice";
    saveNoticeBtn.tabIndex = -1;
    saveNoticeBtn.textContent = "Save notice";
    saveNoticeBtn.addEventListener("mousedown", (e) => e.preventDefault());
    saveNoticeBtn.addEventListener("click", (e) => {
      e.preventDefault();
      const html = getTrixSelectedHTML(editorEl);
      if (!html) {
        alert("Select some text in the intro first, then save it as a notice.");
        return;
      }
      hook.pushEvent("save-selection-as-notice", { html });
    });
    fileTools.appendChild(saveNoticeBtn);
  }
}

function getTrixSelectedHTML(editorEl) {
  const editor = editorEl && editorEl.editor;
  if (!editor) return null;

  const range = editor.getSelectedRange();
  if (!range || range[0] === range[1]) return null;

  const selection = window.getSelection();
  if (selection && selection.rangeCount > 0) {
    const anchor = selection.anchorNode;
    if (anchor && editorEl.contains(anchor)) {
      const container = document.createElement("div");
      for (let i = 0; i < selection.rangeCount; i++) {
        container.appendChild(selection.getRangeAt(i).cloneContents());
      }
      const html = container.innerHTML.trim();
      if (html) return html;
    }
  }

  const text = editor.getDocument().getStringAtRange(range).trim();
  if (!text) return null;
  return text
    .split(/\n+/)
    .map((line) => `<div>${escapeHtml(line)}</div>`)
    .join("");
}

function escapeHtml(text) {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function imageContentTypeFromUrl(url) {
  const path = (url || "").split("?")[0].toLowerCase();
  if (path.endsWith(".png")) return "image/png";
  if (path.endsWith(".gif")) return "image/gif";
  if (path.endsWith(".webp")) return "image/webp";
  if (path.endsWith(".avif")) return "image/avif";
  if (path.endsWith(".svg")) return "image/svg+xml";
  if (path.endsWith(".jpg") || path.endsWith(".jpeg")) return "image/jpeg";
  return "image/jpeg";
}

module.exports = {
  mounted() {
    window.Trix = Trix;

    this.onTrixChange = () => {
      requestAnimationFrame(() => emitEditorUpdateEvent(this, this.el));
    };
    this.onTrixBlur = () => {
      emitEditorUpdateEvent(this, this.el);
    };
    this.onTrixAttachmentAdd = (event) => {
      if (event.attachment.file) {
        const postID = this.el.getAttribute("data-post-id");
        const editorEl = document.querySelector(
          `trix-editor[input="${this.el.id}"]`,
        );
        uploadFileAttachment(event.attachment, postID, editorEl);
      }
    };
    this.onTrixInitialize = (event) => {
      if (event.target.getAttribute("input") === this.el.id) {
        addCustomToolbarButtons(event.target, this);
      }
    };

    document.addEventListener("trix-change", this.onTrixChange);
    document.addEventListener("trix-blur", this.onTrixBlur);
    document.addEventListener("trix-attachment-add", this.onTrixAttachmentAdd);

    this.handleEvent("insert-trix-image", ({ url, href, alt, target_input_id }) => {
      if (this.el.id !== target_input_id) return;
      const editorEl = document.querySelector(
        `trix-editor[input="${target_input_id}"]`,
      );
      if (!editorEl) return;
      // Always set href so Trix wraps the preview in <a> (needed for lightbox + download).
      const imageHref = href || `${url}?content-disposition=attachment`;
      const attachment = new Trix.Attachment({
        url,
        href: imageHref,
        alt,
        contentType: imageContentTypeFromUrl(url),
      });
      editorEl.editor.insertAttachment(attachment);
    });

    this.handleEvent("insert-trix-html", ({ html, target_input_id }) => {
      if (this.el.id !== target_input_id) return;
      if (!html) return;
      const editorEl = document.querySelector(
        `trix-editor[input="${target_input_id}"]`,
      );
      if (!editorEl || !editorEl.editor) return;
      editorEl.editor.insertHTML(html);
    });

    const editorEl = document.querySelector(
      `trix-editor[input="${this.el.id}"]`,
    );
    if (editorEl && editorEl.editor) {
      addCustomToolbarButtons(editorEl, this);
    }

    document.addEventListener("trix-initialize", this.onTrixInitialize);
  },

  destroyed() {
    document.removeEventListener("trix-change", this.onTrixChange);
    document.removeEventListener("trix-blur", this.onTrixBlur);
    document.removeEventListener("trix-attachment-add", this.onTrixAttachmentAdd);
    document.removeEventListener("trix-initialize", this.onTrixInitialize);
  },

  updated() {},
};
