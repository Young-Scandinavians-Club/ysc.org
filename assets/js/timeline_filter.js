export default {
    mounted() {
        this.filterButtons = this.el.querySelectorAll("[data-filter]");
        this.timelineItems = document.querySelectorAll("[data-timeline-item]");

        this.filterButtons.forEach((button) => {
            button.addEventListener("click", (e) => {
                e.preventDefault();
                const filter = button.getAttribute("data-filter");

                // Update button states
                this.filterButtons.forEach((btn) => {
                    if (btn === button) {
                        btn.classList.add("bg-blue-600", "text-white");
                        btn.classList.remove("bg-zinc-100", "text-zinc-600", "hover:bg-zinc-200");
                    } else {
                        btn.classList.remove("bg-blue-600", "text-white");
                        btn.classList.add("bg-zinc-100", "text-zinc-600", "hover:bg-zinc-200");
                    }
                });

                // Filter timeline items
                this.timelineItems.forEach((item) => {
                    const itemTags = item.getAttribute("data-tags") || "";
                    const tags = itemTags.split(",").map((tag) => tag.trim().toLowerCase());
                    const filterLower = filter.toLowerCase();

                    if (filter === "all" || tags.some((tag) => tag === filterLower || tag.includes(filterLower) || filterLower.includes(tag))) {
                        item.classList.remove("hidden");
                        // Smooth scroll reveal
                        item.style.opacity = "0";
                        setTimeout(() => {
                            item.style.transition = "opacity 0.3s ease-in";
                            item.style.opacity = "1";
                        }, 10);
                    } else {
                        item.style.transition = "opacity 0.2s ease-out";
                        item.style.opacity = "0";
                        setTimeout(() => {
                            item.classList.add("hidden");
                        }, 200);
                    }
                });
            });
        });
    },

    destroyed() {
        // Cleanup if needed
    }
};

