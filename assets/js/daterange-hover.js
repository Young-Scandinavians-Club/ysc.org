const DaterangeHover = {
    mounted() {
        // Get the component ID from data attribute first (most reliable)
        let componentId = this.el.getAttribute("data-component-id");

        // If not found, try to extract from phx-target
        if (!componentId) {
            const targetSelector = this.el.getAttribute("phx-target");
            if (targetSelector) {
                // phx-target is like "#phx-F3-..." - extract the ID
                // Remove the # prefix if present
                const idFromTarget = targetSelector.replace(/^#/, "");

                // Try to find the component element
                let componentEl = null;

                // Try using getElementById first (safest)
                if (idFromTarget) {
                    try {
                        componentEl = document.getElementById(idFromTarget);
                    } catch (e) {
                        // Invalid ID, skip
                    }
                }

                // If that didn't work, try querySelector with the full selector
                if (!componentEl && targetSelector.startsWith("#")) {
                    try {
                        componentEl = document.querySelector(targetSelector);
                    } catch (e) {
                        // Invalid selector, skip
                    }
                }

                // If we found an element, use its ID
                if (componentEl && componentEl.id) {
                    componentId = componentEl.id;
                } else if (idFromTarget) {
                    // Use the ID from the selector directly
                    componentId = idFromTarget;
                }
            }
        }

        // Store component ID for use in event handlers
        this.componentId = componentId;
        console.log("[DaterangeHover] Component ID:", componentId);

        // Find the component element for pushEventTo
        // LiveView components have a root element with data-phx-component attribute
        this.componentEl = null;
        if (componentId) {
            // First try to find by ID
            try {
                this.componentEl = document.getElementById(componentId);
                if (this.componentEl) {
                    console.log("[DaterangeHover] Found component by ID:", this.componentEl);
                }
            } catch (e) {
                // Invalid ID, skip
                console.warn("[DaterangeHover] Invalid component ID:", e);
            }

            // If not found, try to find by data-phx-component attribute
            if (!this.componentEl) {
                try {
                    this.componentEl = document.querySelector(`[data-phx-component="${componentId}"]`);
                    if (this.componentEl) {
                        console.log("[DaterangeHover] Found component by data-phx-component:", this.componentEl);
                    }
                } catch (e) {
                    // Invalid selector, skip
                    console.warn("[DaterangeHover] Invalid selector:", e);
                }
            }

            // If still not found, try to find from a button's phx-target
            if (!this.componentEl) {
                const buttonWithTarget = this.el.querySelector(`button[phx-target]`);
                if (buttonWithTarget) {
                    const targetSelector = buttonWithTarget.getAttribute("phx-target");
                    console.log("[DaterangeHover] Found button with phx-target:", targetSelector);
                    if (targetSelector) {
                        try {
                            // Try to find the component element using the phx-target selector
                            this.componentEl = document.querySelector(targetSelector);
                            if (this.componentEl) {
                                console.log("[DaterangeHover] Found component from phx-target:", this.componentEl);
                            } else {
                                // If selector doesn't work, try to find the parent component
                                // by walking up the DOM tree
                                let parent = this.el.parentElement;
                                while (parent && !this.componentEl) {
                                    if (parent.hasAttribute && parent.hasAttribute("data-phx-component")) {
                                        const parentComponentId = parent.getAttribute("data-phx-component");
                                        if (parentComponentId === componentId) {
                                            this.componentEl = parent;
                                            console.log("[DaterangeHover] Found component by walking up DOM:", this.componentEl);
                                            break;
                                        }
                                    }
                                    parent = parent.parentElement;
                                }
                            }
                        } catch (e) {
                            // Invalid selector, skip
                            console.warn("[DaterangeHover] Invalid phx-target selector:", e);
                        }
                    }
                }
            }

            // If still not found, try to find by walking up from the hook element
            if (!this.componentEl && componentId) {
                let parent = this.el.parentElement;
                while (parent && !this.componentEl) {
                    if (parent.id === componentId ||
                        (parent.hasAttribute && parent.getAttribute("data-phx-component") === componentId)) {
                        this.componentEl = parent;
                        console.log("[DaterangeHover] Found component by walking up DOM tree:", this.componentEl);
                        break;
                    }
                    parent = parent.parentElement;
                }
            }

            if (!this.componentEl) {
                console.warn("[DaterangeHover] Could not find component element with ID:", componentId);
            }
        }

        this.el.addEventListener("mouseover", (e) => {
            // Find the closest button element (event target might be a child like <time>)
            const button = e.target.closest("button[phx-value-date]");

            if (button && button.hasAttribute("phx-value-date") && !button.disabled) {
                const date = button.getAttribute("phx-value-date");
                console.log("[DaterangeHover] mouseover on date:", date, "componentId:", this.componentId, "componentEl:", this.componentEl);

                // Try multiple methods to push the event
                let eventPushed = false;

                if (this.componentEl) {
                    // Use the component element directly
                    try {
                        console.log("[DaterangeHover] Pushing to component element");
                        this.pushEventTo(this.componentEl, "cursor-move", date);
                        eventPushed = true;
                    } catch (e) {
                        console.warn("[DaterangeHover] Failed to push event to component element:", e);
                    }
                }

                if (!eventPushed && this.componentId) {
                    // Fallback: try using the ID as a selector
                    try {
                        console.log("[DaterangeHover] Pushing to component with selector:", `#${this.componentId}`);
                        this.pushEventTo(`#${this.componentId}`, "cursor-move", date);
                        eventPushed = true;
                    } catch (e) {
                        console.warn("[DaterangeHover] Failed to push event with selector:", e);
                    }
                }

                if (!eventPushed) {
                    // Final fallback: push to parent LiveView
                    console.log("[DaterangeHover] Falling back to parent LiveView");
                    this.pushEvent("cursor-move", date);
                }
            }
        });

        // Handle mouse leave to clear hover
        this.el.addEventListener("mouseleave", () => {
            let eventPushed = false;

            if (this.componentEl) {
                try {
                    this.pushEventTo(this.componentEl, "cursor-leave", {});
                    eventPushed = true;
                } catch (e) {
                    console.warn("Failed to push cursor-leave to component element:", e);
                }
            }

            if (!eventPushed && this.componentId) {
                try {
                    this.pushEventTo(`#${this.componentId}`, "cursor-leave", {});
                    eventPushed = true;
                } catch (e) {
                    console.warn("Failed to push cursor-leave with selector:", e);
                }
            }

            if (!eventPushed) {
                this.pushEvent("cursor-leave", {});
            }
        });
    },
};

export default DaterangeHover;