import Trix from "../vendor/trix";

function emitEditorUpdateEvent(source, el) {
  if (!el) return;
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
      let url;
      try {
        const data = JSON.parse(xhr.responseText);
        url = data.url;
        const attributes = { url, href: `${url}?content-disposition=attachment` };
        successCallback(attributes);
      } catch (_e) {
        // Fallback for plain-text URL response
        url = xhr.responseText;
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
      if (typeof errorCallback === "function") {
        errorCallback(message);
      }
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

    document.addEventListener("trix-change", () => {
      // Defer one microtask to ensure Trix has fully synced the hidden input
      // value before we read it. Trix 2.x may dispatch trix-change before
      // completing the hidden-input sync for certain operations (e.g. hard
      // breaks inserted via Shift+Enter).
      requestAnimationFrame(() => emitEditorUpdateEvent(this, this.el));
    });

    document.addEventListener("trix-blur", () => {
      emitEditorUpdateEvent(this, this.el);
    });

    document.addEventListener("trix-attachment-add", (event) => {
      if (event.attachment.file) {
        const postID = this.el.getAttribute("data-post-id");
        const editorEl = document.querySelector(
          `trix-editor[input="${this.el.id}"]`,
        );
        uploadFileAttachment(event.attachment, postID, editorEl);
      }
    });

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

    const hookEl = this.el;
    document.addEventListener("trix-initialize", (event) => {
      if (event.target.getAttribute("input") === hookEl.id) {
        addCustomToolbarButtons(event.target, hookEl);
      }
    });
  },

  updated() {},
};
