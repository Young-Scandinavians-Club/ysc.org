// UnsavedChangesGuard — asks the browser to confirm a reload, tab close or
// external navigation while a form has unsaved edits.
//
// The server owns the dirty state and renders it as `data-dirty`; the hook only
// mirrors it onto a `beforeunload` listener. In-app navigation (closing the
// modal, patching to another tab) is handled server-side, where the form can
// show its own confirmation instead of a native dialog.

export default {
  mounted() {
    this.onBeforeUnload = (event) => {
      event.preventDefault();
      // Required by older browsers to trigger the prompt.
      event.returnValue = "";
    };
    this.sync();
  },

  updated() {
    this.sync();
  },

  destroyed() {
    this.detach();
  },

  sync() {
    if (this.el.dataset.dirty === "true") {
      if (!this.attached) {
        window.addEventListener("beforeunload", this.onBeforeUnload);
        this.attached = true;
      }
    } else {
      this.detach();
    }
  },

  detach() {
    if (this.attached) {
      window.removeEventListener("beforeunload", this.onBeforeUnload);
      this.attached = false;
    }
  },
};
