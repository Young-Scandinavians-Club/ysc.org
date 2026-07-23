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

        // Find the component element for pushEventTo
        // LiveView components have a root element with data-phx-component attribute
        this.componentEl = null;
        if (componentId) {
            // First try to find by ID
            try {
                this.componentEl = document.getElementById(componentId);
            } catch (e) {
                // Invalid ID, skip
            }

            // If not found, try to find by data-component-id attribute
            if (!this.componentEl) {
                try {
                    this.componentEl = document.querySelector(`[data-component-id="${componentId}"]`);
                } catch (e) {
                    // Invalid selector, skip
                }
            }

            // If still not found, try to find from a button's phx-target
            if (!this.componentEl) {
                const buttonWithTarget = this.el.querySelector(`button[phx-target]`);
                if (buttonWithTarget) {
                    const targetSelector = buttonWithTarget.getAttribute("phx-target");
                    if (targetSelector) {
                        try {
                            // Try to find the component element using the phx-target selector
                            this.componentEl = document.querySelector(targetSelector);
                            if (!this.componentEl) {
                                // If selector doesn't work, try to find the parent component
                                // by walking up the DOM tree
                                let parent = this.el.parentElement;
                                while (parent && !this.componentEl) {
                                    if (parent.hasAttribute && parent.hasAttribute("data-component-id")) {
                                        const parentComponentId = parent.getAttribute("data-component-id");
                                        if (parentComponentId === componentId) {
                                            this.componentEl = parent;
                                            break;
                                        }
                                    }
                                    parent = parent.parentElement;
                                }
                            }
                        } catch (e) {
                            // Invalid selector, skip
                        }
                    }
                }
            }

            // If still not found, try to find by walking up from the hook element
            if (!this.componentEl && componentId) {
                let parent = this.el.parentElement;
                while (parent && !this.componentEl) {
                    if (parent.id === componentId ||
                        (parent.hasAttribute && parent.getAttribute("data-component-id") === componentId)) {
                        this.componentEl = parent;
                        break;
                    }
                    parent = parent.parentElement;
                }
            }
        }

        this.onMouseOver = (e) => {
            // Find the closest button element (event target might be a child like <span>)
            const button = e.target.closest("button[phx-value-date]");

            if (button && button.hasAttribute("phx-value-date") && !this.isDayDisabled(button)) {
                const date = button.getAttribute("phx-value-date");

                // Try multiple methods to push the event
                let eventPushed = false;

                if (this.componentEl) {
                    // Use the component element directly
                    try {
                        this.pushEventTo(this.componentEl, "cursor-move", date);
                        eventPushed = true;
                    } catch (e) {
                        // Failed to push event to component element
                    }
                }

                if (!eventPushed && this.componentId) {
                    // Fallback: try using the ID as a selector
                    try {
                        this.pushEventTo(`#${this.componentId}`, "cursor-move", date);
                        eventPushed = true;
                    } catch (e) {
                        // Failed to push event with selector
                    }
                }

                if (!eventPushed) {
                    // Final fallback: push to parent LiveView
                    this.pushEvent("cursor-move", date);
                }
            }
        };

        this.onMouseLeave = () => {
            let eventPushed = false;

            if (this.componentEl) {
                try {
                    this.pushEventTo(this.componentEl, "cursor-leave", {});
                    eventPushed = true;
                } catch (e) {
                    // Failed to push cursor-leave to component element
                }
            }

            if (!eventPushed && this.componentId) {
                try {
                    this.pushEventTo(`#${this.componentId}`, "cursor-leave", {});
                    eventPushed = true;
                } catch (e) {
                    // Failed to push cursor-leave with selector
                }
            }

            if (!eventPushed) {
                this.pushEvent("cursor-leave", {});
            }
        };

        this.onKeyDown = (e) => {
            const button = e.target.closest("button[data-calendar-day]");
            if (!button || !this.el.contains(button)) return;

            const directions = {
                ArrowLeft: -1,
                ArrowRight: 1,
                ArrowUp: -7,
                ArrowDown: 7,
            };

            const delta = directions[e.key];
            if (!delta) return;

            e.preventDefault();

            const days = Array.from(this.el.querySelectorAll("button[data-calendar-day]"));
            const index = days.indexOf(button);
            if (index === -1) return;

            const nextIndex = index + delta;
            if (nextIndex < 0 || nextIndex >= days.length) return;

            days.forEach((day) => day.setAttribute("tabindex", "-1"));
            const next = days[nextIndex];
            next.setAttribute("tabindex", "0");
            next.focus();
        };

        this.el.addEventListener("mouseover", this.onMouseOver);
        this.el.addEventListener("mouseleave", this.onMouseLeave);
        this.el.addEventListener("keydown", this.onKeyDown);
    },

    destroyed() {
        if (this.onMouseOver) {
            this.el.removeEventListener("mouseover", this.onMouseOver);
        }
        if (this.onMouseLeave) {
            this.el.removeEventListener("mouseleave", this.onMouseLeave);
        }
        if (this.onKeyDown) {
            this.el.removeEventListener("keydown", this.onKeyDown);
        }
    },

    isDayDisabled(button) {
        return button.getAttribute("aria-disabled") === "true";
    },
};

export default DaterangeHover;
