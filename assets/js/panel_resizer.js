import { pushEventIfConnected } from "./live_view_safe_push";

// Resizes the right-hand panel by dragging its left edge. Uses Pointer Events so
// mouse, touch, and pen input all work; the edge element sets `touch-action: none`
// so a horizontal swipe resizes instead of scrolling the page.
const PanelResizer = {
    mounted() {
        this.tracking = false;
        this.pointerId = null;
        this.startWidth = null;
        this.startClientX = null;
        this.maxWidth = null;
        this.minWidth = null;

        this.startResize = this.startResize.bind(this);
        this.doResize = this.doResize.bind(this);
        this.stopResize = this.stopResize.bind(this);
        this.handlePointerEnter = this.handlePointerEnter.bind(this);
        this.handlePointerLeave = this.handlePointerLeave.bind(this);

        this.setupResizer();
    },

    updated() {
        // Only re-setup if not currently tracking
        if (!this.tracking) {
            this.setupResizer();
        }
    },

    destroyed() {
        this.detachEdgeListeners();
        document.body.style.cursor = "";
        document.body.style.userSelect = "";
    },

    setupResizer() {
        const leftEdgeId =
            this.el.getAttribute("data-left-edge-id") || "panel-resizer-left-edge";
        const leftEdge = document.getElementById(leftEdgeId);

        if (!leftEdge) {
            console.warn("PanelResizer: Left edge element not found", { id: leftEdgeId });
            return;
        }

        if (leftEdge === this.leftEdge) return;

        this.detachEdgeListeners();
        this.leftEdge = leftEdge;

        leftEdge.addEventListener("pointerdown", this.startResize);
        leftEdge.addEventListener("pointermove", this.doResize);
        leftEdge.addEventListener("pointerup", this.stopResize);
        leftEdge.addEventListener("pointercancel", this.stopResize);
        leftEdge.addEventListener("lostpointercapture", this.stopResize);
        leftEdge.addEventListener("pointerenter", this.handlePointerEnter);
        leftEdge.addEventListener("pointerleave", this.handlePointerLeave);
    },

    detachEdgeListeners() {
        const leftEdge = this.leftEdge;
        if (!leftEdge) return;

        leftEdge.removeEventListener("pointerdown", this.startResize);
        leftEdge.removeEventListener("pointermove", this.doResize);
        leftEdge.removeEventListener("pointerup", this.stopResize);
        leftEdge.removeEventListener("pointercancel", this.stopResize);
        leftEdge.removeEventListener("lostpointercapture", this.stopResize);
        leftEdge.removeEventListener("pointerenter", this.handlePointerEnter);
        leftEdge.removeEventListener("pointerleave", this.handlePointerLeave);
        this.leftEdge = null;
    },

    setHighlight(state) {
        const border = { idle: "border-zinc-300", hover: "border-blue-400", active: "border-blue-500" };
        const text = { idle: "text-zinc-400", hover: "text-blue-400", active: "text-blue-500" };

        this.el.classList.remove(...Object.values(border));
        this.el.classList.add(border[state]);

        const icon = this.el.querySelector(".hero-arrows-right-left");
        if (icon) {
            icon.classList.remove(...Object.values(text));
            icon.classList.add(text[state]);
        }
    },

    handlePointerEnter(event) {
        if (!this.tracking && event.pointerType === "mouse") {
            this.setHighlight("hover");
        }
    },

    handlePointerLeave(event) {
        if (!this.tracking && event.pointerType === "mouse") {
            this.setHighlight("idle");
        }
    },

    startResize(event) {
        // Only the primary mouse button; touch and pen report button 0 too
        if (this.tracking || !event.isPrimary || event.button !== 0) return;

        const parentElement = this.el.parentElement;
        if (!parentElement) return;

        event.preventDefault();

        this.startWidth = this.el.getBoundingClientRect().width;
        this.startClientX = event.clientX;

        const parentWidth = parentElement.getBoundingClientRect().width;
        this.minWidth = parentWidth * 0.2; // 20% minimum
        this.maxWidth = parentWidth * 0.8; // 80% maximum

        this.tracking = true;
        this.pointerId = event.pointerId;

        // Capture keeps pointermove flowing to the edge even when the finger or
        // cursor passes over the email preview iframe or outside the window.
        try {
            this.leftEdge.setPointerCapture(event.pointerId);
        } catch (_) {}

        document.body.style.cursor = "col-resize";
        document.body.style.userSelect = "none";

        this.el.style.transition = "none";
        this.setHighlight("active");
    },

    doResize(event) {
        if (!this.tracking || event.pointerId !== this.pointerId) return;

        event.preventDefault();

        // Dragging right (positive delta) narrows the right panel; left widens it
        const delta = event.clientX - this.startClientX;
        const newWidth = Math.max(this.minWidth, Math.min(this.maxWidth, this.startWidth - delta));

        this.el.style.width = `${newWidth}px`;
        this.el.style.flexShrink = "0";
    },

    stopResize(event) {
        if (!this.tracking || event.pointerId !== this.pointerId) return;

        this.tracking = false;
        this.pointerId = null;

        try {
            if (this.leftEdge?.hasPointerCapture(event.pointerId)) {
                this.leftEdge.releasePointerCapture(event.pointerId);
            }
        } catch (_) {}

        document.body.style.cursor = "";
        document.body.style.userSelect = "";

        this.el.style.transition = "";
        this.setHighlight("idle");

        // Save the width to server
        const width = this.el.style.width;
        if (width) {
            pushEventIfConnected(this, "resize_panel", { width: width });
        }
    },
};

export default PanelResizer;
