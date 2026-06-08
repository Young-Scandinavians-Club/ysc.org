const INACTIVE_CLASSES = ["border", "border-zinc-300", "text-zinc-500", "hover:border-zinc-400"];
const ACTIVE_CLASSES = ["bg-blue-600", "text-white", "border-blue-600"];

export default {
    mounted() {
        this.filterButtons = this.el.querySelectorAll("[data-filter]");
        this.timelineItems = document.querySelectorAll("[data-timeline-item]");
        this._clickHandlers = [];

        this.filterButtons.forEach((button) => {
            const handler = (e) => {
                e.preventDefault();
                const filter = button.getAttribute("data-filter");

                this.filterButtons.forEach((btn) => {
                    const isActive = btn === button;
                    btn.setAttribute("data-active", isActive ? "true" : "false");
                    this.setButtonState(btn, isActive);
                });

                let visibleCount = 0;
                this.timelineItems.forEach((item) => {
                    const itemTags = item.getAttribute("data-tags") || "";
                    const tags = itemTags.split(",").map((tag) => tag.trim().toLowerCase());
                    const filterLower = filter.toLowerCase();

                    if (filter === "all" || tags.some((tag) => tag === filterLower || tag.includes(filterLower) || filterLower.includes(tag))) {
                        item.classList.remove("hidden");
                        item.style.opacity = "0";
                        item.style.transform = "translateY(12px)";
                        const delay = visibleCount * 50;
                        visibleCount++;
                        setTimeout(() => {
                            item.style.transition = "opacity 0.5s ease-out, transform 0.5s ease-out";
                            item.style.opacity = "1";
                            item.style.transform = "translateY(0)";
                        }, 10 + delay);
                    } else {
                        item.style.transition = "opacity 0.3s ease-out, transform 0.3s ease-out";
                        item.style.opacity = "0";
                        item.style.transform = "translateY(-8px)";
                        setTimeout(() => {
                            item.classList.add("hidden");
                        }, 300);
                    }
                });
            };

            button.addEventListener("click", handler);
            this._clickHandlers.push({ button, handler });
        });
    },

    setButtonState(button, isActive) {
        button.classList.remove(...INACTIVE_CLASSES, ...ACTIVE_CLASSES, "border");

        if (isActive) {
            button.classList.add(...ACTIVE_CLASSES);
        } else {
            button.classList.add(...INACTIVE_CLASSES);
        }
    },

    destroyed() {
        if (this._clickHandlers) {
            this._clickHandlers.forEach(({ button, handler }) => {
                button.removeEventListener("click", handler);
            });
            this._clickHandlers = null;
        }

        this.filterButtons = null;
        this.timelineItems = null;
    }
};
