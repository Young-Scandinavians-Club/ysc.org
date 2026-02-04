import Trix from "../vendor/trix";

function emitEditorUpdateEvent(source) {
  const editorElement = document.getElementById("post[raw_body]");
  source.pushEvent("editor-update", { raw_body: editorElement.value });
}

function uploadFileAttachment(attachment, postID) {
  uploadFile(attachment.file, postID, setProgress, setAttributes);

  function setProgress(progress) {
    attachment.setUploadProgress(progress);
  }

  function setAttributes(attributes) {
    attachment.setAttributes(attributes);
  }
}

function uploadFile(file, postID, progressCallback, successCallback) {
  const formData = new FormData();
  formData.append("file", file);
  formData.append("post_id", postID);
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
      const url = xhr.responseText;
      const attributes = { url, href: `${url}?content-disposition=attachment` };
      successCallback(attributes);
    }
  });

  xhr.send(formData);
}

module.exports = {
  mounted() {
    window.Trix = Trix;

    document.addEventListener("trix-change", () => {
      emitEditorUpdateEvent(this);
    });

    document.addEventListener("trix-blur", () => {
      emitEditorUpdateEvent(this);
    });

    document.addEventListener("trix-attachment-add", (event) => {
      const postID = this.el.getAttribute("data-post-id");
      uploadFileAttachment(event.attachment, postID);
    });
  },

  updated() { },
};
