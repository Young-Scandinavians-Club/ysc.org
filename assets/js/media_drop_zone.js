let MediaDropZone = {
    mounted() {
        this.container = this.el;
        this.dragCounter = 0;
        this.dropUploadForm = document.getElementById("media-drop-upload-form");

        // Bind event handlers
        this.handleDragEnter = this.handleDragEnter.bind(this);
        this.handleDragLeave = this.handleDragLeave.bind(this);
        this.handleDragOver = this.handleDragOver.bind(this);
        this.handleDrop = this.handleDrop.bind(this);

        // Add drag event listeners to document
        document.addEventListener("dragenter", this.handleDragEnter);
        document.addEventListener("dragleave", this.handleDragLeave);
        document.addEventListener("dragover", this.handleDragOver);
        document.addEventListener("drop", this.handleDrop);
    },

    destroyed() {
        // Clean up event listeners
        document.removeEventListener("dragenter", this.handleDragEnter);
        document.removeEventListener("dragleave", this.handleDragLeave);
        document.removeEventListener("dragover", this.handleDragOver);
        document.removeEventListener("drop", this.handleDrop);
    },

    updated() {
        this.dropUploadForm = document.getElementById("media-drop-upload-form");
    },

    handleDragEnter(e) {
        // Only handle file drags
        if (!this.hasFiles(e)) return;

        e.preventDefault();
        this.dragCounter++;

        if (this.dragCounter === 1) {
            // Show drop zone overlay
            this.pushEvent("show-drop-zone", {});
        }
    },

    handleDragLeave(e) {
        // Only handle file drags
        if (!this.hasFiles(e)) return;

        e.preventDefault();
        this.dragCounter--;

        if (this.dragCounter === 0) {
            // Hide drop zone overlay
            this.pushEvent("hide-drop-zone", {});
        }
    },

    handleDragOver(e) {
        // Only handle file drags
        if (!this.hasFiles(e)) return;

        e.preventDefault();
        e.dataTransfer.dropEffect = "copy";
    },

    handleDrop(e) {
        // Only handle file drags
        if (!this.hasFiles(e)) return;

        e.preventDefault();
        this.dragCounter = 0;

        // Hide drop zone overlay
        this.pushEvent("hide-drop-zone", {});

        // Phoenix handles the drop via phx-drop-target. Submit on the next tick
        // so the dropped files are registered before the server consumes them.
        if (this.dropUploadForm) {
            setTimeout(() => this.submitDropUploadForm(), 0);
        }
    },

    hasFiles(e) {
        // Check if the drag contains files
        if (!e.dataTransfer || !e.dataTransfer.types) return false;
        return Array.from(e.dataTransfer.types).includes("Files");
    },

    submitDropUploadForm() {
        const form = document.getElementById("media-drop-upload-form");
        if (!form) return;

        if (typeof form.requestSubmit === "function") {
            form.requestSubmit();
        } else {
            form.dispatchEvent(
                new Event("submit", { bubbles: true, cancelable: true })
            );
        }
    },
};

export default MediaDropZone;
