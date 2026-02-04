export default {
    mounted() {
        this.handleScrollSpy();
        this.handleProgressIndicator();
    },

    handleScrollSpy() {
        const navLinks = this.el.querySelectorAll(".nav-link");

        // Select all section targets
        const targets = document.querySelectorAll(
            "#arrival-section, #the-stay-section, #club-standards-section, #boating-section, #quiet-hours-section, #pets-section, #facilities-section"
        );

        // Track which sections are currently intersecting
        this.intersectingSections = new Map();

        const observerOptions = {
            root: null,
            rootMargin: "-10% 0px -70% 0px",
            threshold: [0, 0.1, 0.5, 1.0]
        };

        const observer = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                const id = entry.target.getAttribute("id");

                if (entry.isIntersecting) {
                    this.intersectingSections.set(id, entry.intersectionRatio);
                } else {
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
                const isActive = targetId === activeId;

                if (isActive) {
                    link.classList.add("font-bold", "text-teal-700");
                    link.classList.remove("text-teal-600", "text-zinc-500");
                } else {
                    link.classList.remove("font-bold", "text-teal-700");
                    if (link.classList.contains("text-xs")) {
                        link.classList.add("text-zinc-500");
                        link.classList.remove("text-teal-600");
                    } else {
                        link.classList.add("text-teal-600");
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

    handleProgressIndicator() {
        const progressFill = this.el.querySelector("#nav-progress-fill");
        if (!progressFill) return;

        const updateProgress = () => {
            const scrollTop = window.scrollY || document.documentElement.scrollTop;
            const scrollHeight = document.documentElement.scrollHeight - document.documentElement.clientHeight;
            const scrollProgress = scrollHeight > 0 ? (scrollTop / scrollHeight) * 100 : 0;

            // Get the height of the navigation container
            const navHeight = this.el.offsetHeight;
            const progressHeight = (scrollProgress / 100) * navHeight;

            progressFill.style.height = `${Math.min(progressHeight, navHeight)}px`;
        };

        // Update on scroll
        window.addEventListener("scroll", updateProgress);
        updateProgress(); // Initial update

        // Store cleanup function
        this.progressCleanup = () => {
            window.removeEventListener("scroll", updateProgress);
        };
    },

    destroyed() {
        if (this.observer) {
            this.observer.disconnect();
        }
        if (this.progressCleanup) {
            this.progressCleanup();
        }
    }
};