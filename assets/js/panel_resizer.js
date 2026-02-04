const PanelResizer = {
    mounted() {
        this.tracking = false;
        this.startWidth = null;
        this.startCursorScreenX = null;
        this.handleWidth = 8; // 8px for the resizer
        this.resizeTarget = null;
        this.parentElement = null;
        this.maxWidth = null;
        this.minWidth = null;

        // Bind methods to preserve 'this' context
        this.doResize = this.doResize.bind(this);
        this.stopResize = this.stopResize.bind(this);

        this.setupResizer();
    },

    updated() {
        // Only re-setup if not currently tracking
        if (!this.tracking) {
            this.setupResizer();
        }
    },

    setupResizer() {
        const handleElement = this.el;
        if (!handleElement) {
            console.warn("PanelResizer: Handle element not found");
            return;
        }

        // Remove existing event listeners if any
        if (this.mousedownHandler) {
            handleElement.removeEventListener("mousedown", this.mousedownHandler);
        }
        if (this.mouseenterHandler) {
            handleElement.removeEventListener("mouseenter", this.mouseenterHandler);
        }
        if (this.mouseleaveHandler) {
            handleElement.removeEventListener("mouseleave", this.mouseleaveHandler);
        }

        const parentElement = handleElement.parentElement;
        if (!parentElement) {
            console.warn("PanelResizer: Parent element not found");
            return;
        }

        // The handle element IS the resize target (the right panel)
        // We're making the left edge of the panel itself draggable
        const targetElement = handleElement;

        // Store references
        this.parentElement = parentElement;
        this.resizeTarget = targetElement;

        // Find the left edge div by ID (defined in LiveView template)
        const leftEdgeId = handleElement.getAttribute("data-left-edge-id") || "panel-resizer-left-edge";
        const leftEdge = document.getElementById(leftEdgeId);

        if (!leftEdge) {
            console.warn("PanelResizer: Left edge element not found", { id: leftEdgeId });
            return;
        }

        this.leftEdge = leftEdge;

        const startResize = (event) => {
            if (event.button !== 0) {
                return; // Only handle left mouse button
            }

            // Only handle if clicking on the left edge div or within the first 24px (w-6) of the panel
            const panelRect = this.resizeTarget.getBoundingClientRect();
            const clickX = event.clientX - panelRect.left;
            const isLeftEdge = event.target === this.leftEdge || event.target.closest("#panel-resizer-left-edge") || clickX < 24;

            if (!isLeftEdge) {
                return; // Only allow dragging from the left edge
            }

            event.preventDefault();
            event.stopPropagation();
            event.stopImmediatePropagation();

            const targetRect = this.resizeTarget.getBoundingClientRect();
            this.startWidth = targetRect.width;
            this.startCursorScreenX = event.screenX;

            const parentRect = this.parentElement.getBoundingClientRect();
            this.minWidth = parentRect.width * 0.2; // 20% minimum
            this.maxWidth = parentRect.width * 0.8; // 80% maximum

            this.tracking = true;

            // Add global event listeners
            document.addEventListener("mousemove", this.doResize);
            document.addEventListener("mouseup", this.stopResize);

            // Change cursor
            document.body.style.cursor = "col-resize";
            document.body.style.userSelect = "none";

            // Disable transitions and add highlight
            this.resizeTarget.style.transition = "none";
            this.resizeTarget.classList.add("border-blue-500");
            this.resizeTarget.classList.remove("border-zinc-300");

            // Update icon color
            const icon = this.resizeTarget.querySelector(".hero-arrows-right-left");
            if (icon) {
                icon.classList.remove("text-zinc-400");
                icon.classList.add("text-blue-500");
            }

            console.log("PanelResizer: Tracking started", {
                startWidth: this.startWidth,
                startCursorScreenX: this.startCursorScreenX
            });
        };

        const handleMouseEnter = () => {
            if (!this.tracking) {
                this.resizeTarget.classList.add("border-blue-400");
                this.resizeTarget.classList.remove("border-zinc-300");

                // Update icon color on hover
                const icon = this.resizeTarget.querySelector(".hero-arrows-right-left");
                if (icon) {
                    icon.classList.remove("text-zinc-400");
                    icon.classList.add("text-blue-400");
                }
            }
        };

        const handleMouseLeave = () => {
            if (!this.tracking) {
                this.resizeTarget.classList.remove("border-blue-400");
                this.resizeTarget.classList.add("border-zinc-300");

                // Reset icon color
                const icon = this.resizeTarget.querySelector(".hero-arrows-right-left");
                if (icon) {
                    icon.classList.remove("text-blue-400");
                    icon.classList.add("text-zinc-400");
                }
            }
        };

        this.mousedownHandler = startResize;
        this.mouseenterHandler = handleMouseEnter;
        this.mouseleaveHandler = handleMouseLeave;

        // Listen on the left edge and the panel itself
        if (this.leftEdge) {
            this.leftEdge.addEventListener("mousedown", startResize);
        }
        handleElement.addEventListener("mousedown", startResize);
        handleElement.addEventListener("mouseenter", handleMouseEnter);
        handleElement.addEventListener("mouseleave", handleMouseLeave);
    },

    doResize(event) {
        if (!this.tracking) return;

        const cursorScreenXDelta = event.screenX - this.startCursorScreenX;
        // When dragging right (positive delta), the right panel should get narrower (subtract)
        // When dragging left (negative delta), the right panel should get wider (add)
        let newWidth = this.startWidth - cursorScreenXDelta;

        // Constrain the width
        newWidth = Math.max(this.minWidth, Math.min(this.maxWidth, newWidth));

        // Set the width directly
        this.resizeTarget.style.width = `${newWidth}px`;
        this.resizeTarget.style.flexShrink = "0";
    },

    stopResize(event) {
        if (!this.tracking) return;

        this.tracking = false;

        // Remove global event listeners
        document.removeEventListener("mousemove", this.doResize);
        document.removeEventListener("mouseup", this.stopResize);

        // Reset cursor
        document.body.style.cursor = "";
        document.body.style.userSelect = "";

        // Re-enable transitions and remove highlight
        this.resizeTarget.style.transition = "";
        this.resizeTarget.classList.remove("border-blue-500");
        this.resizeTarget.classList.add("border-zinc-300");

        // Reset icon color
        const icon = this.resizeTarget.querySelector(".hero-arrows-right-left");
        if (icon) {
            icon.classList.remove("text-blue-500");
            icon.classList.add("text-zinc-400");
        }

        // Save the width to server
        const width = this.resizeTarget.style.width;
        if (width) {
            this.pushEvent("resize_panel", { width: width });
        }

        console.log("PanelResizer: Tracking stopped", { finalWidth: width });
    },
};

export default PanelResizer;