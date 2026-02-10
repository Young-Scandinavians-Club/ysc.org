export default {
    mounted() {
        this.filterButtons = this.el.querySelectorAll("[data-filter]");
        this.timelineItems = document.querySelectorAll("[data-timeline-item]");

        this.filterButtons.forEach((button) => {
            button.addEventListener("click", (e) => {
                e.preventDefault();
                const filter = button.getAttribute("data-filter");

                // Update button states with enhanced styling and pulse animation
                this.filterButtons.forEach((btn) => {
                    if (btn === button) {
                        // Active state with pulse effect
                        btn.classList.add("bg-blue-600", "text-white", "shadow-lg", "scale-105", "ring-4", "ring-blue-200");
                        btn.classList.remove("bg-amber-50", "bg-blue-50", "bg-orange-50", "bg-green-50", "bg-yellow-50");
                        btn.classList.remove("text-amber-700", "text-blue-700", "text-orange-700", "text-green-700", "text-yellow-700");
                        btn.classList.remove("border-amber-200", "border-blue-200", "border-orange-200", "border-green-200", "border-yellow-200");
                        btn.classList.remove("hover:bg-amber-100", "hover:bg-blue-100", "hover:bg-orange-100", "hover:bg-green-100", "hover:bg-yellow-100");
                    } else {
                        // Inactive state - restore original colors
                        btn.classList.remove("bg-blue-600", "text-white", "shadow-lg", "scale-105", "ring-4", "ring-blue-200");
                        
                        const originalFilter = btn.getAttribute("data-filter");
                        if (originalFilter === "founding") {
                            btn.classList.add("bg-amber-50", "text-amber-700", "border-amber-200", "hover:bg-amber-100");
                        } else if (originalFilter === "club leadership") {
                            btn.classList.add("bg-blue-50", "text-blue-700", "border-blue-200", "hover:bg-blue-100");
                        } else if (originalFilter === "real estate") {
                            btn.classList.add("bg-orange-50", "text-orange-700", "border-orange-200", "hover:bg-orange-100");
                        } else if (originalFilter === "cabin life") {
                            btn.classList.add("bg-green-50", "text-green-700", "border-green-200", "hover:bg-green-100");
                        } else if (originalFilter === "anniversary") {
                            btn.classList.add("bg-yellow-50", "text-yellow-700", "border-yellow-200", "hover:bg-yellow-100");
                        }
                    }
                });

                // Filter timeline items with staggered smooth animations
                let visibleCount = 0;
                this.timelineItems.forEach((item, index) => {
                    const itemTags = item.getAttribute("data-tags") || "";
                    const tags = itemTags.split(",").map((tag) => tag.trim().toLowerCase());
                    const filterLower = filter.toLowerCase();

                    if (filter === "all" || tags.some((tag) => tag === filterLower || tag.includes(filterLower) || filterLower.includes(tag))) {
                        item.classList.remove("hidden");
                        // Staggered smooth scroll reveal
                        item.style.opacity = "0";
                        item.style.transform = "translateY(20px) scale(0.98)";
                        const delay = visibleCount * 50; // Stagger by 50ms per visible item
                        visibleCount++;
                        setTimeout(() => {
                            item.style.transition = "opacity 0.5s cubic-bezier(0.4, 0, 0.2, 1), transform 0.5s cubic-bezier(0.4, 0, 0.2, 1)";
                            item.style.opacity = "1";
                            item.style.transform = "translateY(0) scale(1)";
                        }, 10 + delay);
                    } else {
                        // Fade out with scale
                        item.style.transition = "opacity 0.3s ease-out, transform 0.3s ease-out";
                        item.style.opacity = "0";
                        item.style.transform = "translateY(-10px) scale(0.95)";
                        setTimeout(() => {
                            item.classList.add("hidden");
                        }, 300);
                    }
                });
            });
        });
    },

    destroyed() {
        // Cleanup if needed
    }
};

