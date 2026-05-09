let MediaDropZone = {
    mounted() {
        this.container = this.el;
        this.dragCounter = 0;

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

    handleDragEnter(e) {
        // Only handle file drags
        if (!this.hasFiles(e)) return;

        e.preventDefault();
        this.dragCounter++;

        if (this.dragCounter === 1) {
            this.showOverlay();
        }
    },

    handleDragLeave(e) {
        // Only handle file drags
        if (!this.hasFiles(e)) return;

        e.preventDefault();
        this.dragCounter--;
        this.dragCounter = Math.max(0, this.dragCounter);

        if (this.dragCounter === 0) {
            this.hideOverlay();
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
        this.hideOverlay();

        const files = Array.from(e.dataTransfer.files || []);
        if (files.length > 0) {
            // Let LiveView's phx-drop-target handler track the files first.
            setTimeout(() => this.pushEvent("drop-upload-started", {}), 0);
        }
    },

    showOverlay() {
        const overlay = document.querySelector("[data-drop-zone-overlay]");
        if (overlay) overlay.classList.remove("hidden");
    },

    hideOverlay() {
        const overlay = document.querySelector("[data-drop-zone-overlay]");
        if (overlay) overlay.classList.add("hidden");
    },

    hasFiles(e) {
        // Check if the drag contains files
        if (!e.dataTransfer || !e.dataTransfer.types) return false;
        return Array.from(e.dataTransfer.types).includes("Files");
    },
};

export default MediaDropZone;
