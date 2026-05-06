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

function addCustomToolbarButtons(editorEl, hookEl) {
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
        addCustomToolbarButtons(event.target, this.el);
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
      const attachment = new Trix.Attachment({
        url,
        href,
        alt,
        contentType: "image",
      });
      editorEl.editor.insertAttachment(attachment);
    });

    const editorEl = document.querySelector(
      `trix-editor[input="${this.el.id}"]`,
    );
    if (editorEl && editorEl.editor) {
      addCustomToolbarButtons(editorEl, this.el);
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
