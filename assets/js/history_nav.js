export default {
    mounted() {
        this.handleScrollSpy();
    },

    handleScrollSpy() {
        const navLinks = this.el.querySelectorAll(".nav-link");

        // Select all targets: Key Events heading, Presidents heading, and Decade divs
        const targets = document.querySelectorAll("#key-events, #presidents, [id^='presidents-']");

        // Track which sections are currently intersecting
        this.intersectingSections = new Map();

        const observerOptions = {
            root: null,
            // rootMargin: negative top means trigger when section is 10% from top of viewport
            // negative bottom means section needs to be 70% visible to be considered active
            rootMargin: "-10% 0px -70% 0px",
            threshold: [0, 0.1, 0.5, 1.0] // Multiple thresholds for better detection
        };

        const observer = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                const id = entry.target.getAttribute("id");

                if (entry.isIntersecting) {
                    // Store this section as intersecting with its ratio
                    this.intersectingSections.set(id, entry.intersectionRatio);
                } else {
                    // Remove from intersecting sections
                    this.intersectingSections.delete(id);
                }
            });

            // Find the section with the highest intersection ratio
            let activeId = null;
            let maxRatio = 0;

            this.intersectingSections.forEach((ratio, id) => {
                if (ratio > maxRatio) {
                    maxRatio = ratio;
                    activeId = id;
                }
            });

            // If no section is intersecting, check which one is closest above viewport
            if (!activeId && this.intersectingSections.size === 0) {
                const scrollY = window.scrollY;
                let closestId = null;
                let closestDistance = Infinity;

                targets.forEach((target) => {
                    const rect = target.getBoundingClientRect();
                    const targetTop = scrollY + rect.top;

                    // If target is above viewport
                    if (targetTop < scrollY + 200) {
                        const distance = scrollY + 200 - targetTop;
                        if (distance < closestDistance && distance < 500) {
                            closestDistance = distance;
                            closestId = target.getAttribute("id");
                        }
                    }
                });

                if (closestId) {
                    activeId = closestId;
                }
            }

            // Update link highlighting
            navLinks.forEach((link) => {
                const targetId = link.getAttribute("data-nav");
                const isActive =
                    targetId === activeId ||
                    (activeId && activeId.startsWith("presidents-") && targetId === "presidents");

                if (isActive) {
                    link.classList.add("font-bold", "text-blue-700");
                    link.classList.remove("text-blue-600", "text-zinc-500");
                } else {
                    link.classList.remove("font-bold", "text-blue-700");
                    if (link.classList.contains("text-xs")) {
                        link.classList.add("text-zinc-500");
                        link.classList.remove("text-blue-600");
                    } else {
                        link.classList.add("text-blue-600");
                        link.classList.remove("text-zinc-500");
                    }
                }
            });
        }, observerOptions);

        // Observe all targets
        targets.forEach((target) => observer.observe(target));

        // Store observer for cleanup
        this.observer = observer;
    },

    destroyed() {
        if (this.observer) {
            this.observer.disconnect();
        }
    }
};