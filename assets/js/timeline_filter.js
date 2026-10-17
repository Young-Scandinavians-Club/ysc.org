const INACTIVE_CLASSES = ["border", "border-zinc-300", "text-zinc-500", "hover:border-zinc-400"];
const ACTIVE_CLASSES = ["bg-blue-600", "text-white", "border-blue-600"];

const FADE_OUT_MS = 300;

export default {
    mounted() {
        this.motion = window.matchMedia("(prefers-reduced-motion: reduce)");
        this.filterButtons = Array.from(this.el.querySelectorAll("[data-filter]"));
        this.jumpLinks = Array.from(this.el.querySelectorAll("[data-jump]"));
        this.timelineItems = Array.from(document.querySelectorAll("[data-timeline-item]"));
        this.sections = Array.from(document.querySelectorAll("[data-decade-section]"));
        this.activeFilter = "all";

        this.onToolbarClick = (e) => {
            const button = e.target.closest("[data-filter]");
            if (!button || !this.el.contains(button)) return;
            e.preventDefault();
            this.applyFilter(button.getAttribute("data-filter"));
        };

        // Category badges on timeline items act as shortcuts to the same filters.
        // Clicking the badge for the filter that is already on switches it back off.
        this.onTagClick = (e) => {
            const trigger = e.target.closest("[data-filter-trigger]");
            if (!trigger) return;
            e.preventDefault();
            const filter = trigger.getAttribute("data-filter-trigger").toLowerCase();
            this.applyFilter(filter === this.activeFilter ? "all" : filter);
        };

        this.el.addEventListener("click", this.onToolbarClick);
        document.addEventListener("click", this.onTagClick);
        this.observeCurrentSection();
    },

    applyFilter(filter) {
        this.activeFilter = filter;

        this.filterButtons.forEach((button) => {
            const isActive = button.getAttribute("data-filter") === filter;
            button.setAttribute("data-active", isActive ? "true" : "false");
            button.setAttribute("aria-pressed", isActive ? "true" : "false");
            this.setButtonState(button, isActive);
        });

        const animate = !this.motion.matches;
        const decadesWithMatches = new Set();
        let revealed = 0;

        this.timelineItems.forEach((item) => {
            const matches = this.matches(item, filter);

            if (matches) {
                const section = item.closest("[data-decade-section]");
                if (section) decadesWithMatches.add(section.getAttribute("data-decade-section"));
                if (this.reveal(item, animate ? revealed : null)) revealed++;
            } else {
                this.conceal(item, animate);
            }
        });

        // A decade with nothing left in it hides entirely, heading and jump link included.
        this.sections.forEach((section) => {
            const decade = section.getAttribute("data-decade-section");
            const hasMatches = decadesWithMatches.has(decade);

            clearTimeout(section._hideTimer);
            if (hasMatches) {
                section.classList.remove("hidden");
            } else if (animate) {
                section._hideTimer = setTimeout(() => section.classList.add("hidden"), FADE_OUT_MS);
            } else {
                section.classList.add("hidden");
            }

            this.jumpLinks
                .filter((link) => link.getAttribute("data-decade-link") === decade)
                .forEach((link) => link.classList.toggle("hidden", !hasMatches));
        });

        this.keepPlace(animate);
    },

    matches(item, filter) {
        if (filter === "all") return true;
        const tags = (item.getAttribute("data-tags") || "")
            .split(",")
            .map((tag) => tag.trim().toLowerCase());
        return tags.includes(filter);
    },

    // Returns true when the item actually transitioned from hidden to shown.
    reveal(item, order) {
        clearTimeout(item._hideTimer);
        if (item._filterState !== "hidden") return false;
        item._filterState = "shown";
        item.classList.remove("hidden");

        if (order === null) {
            item.style.transition = "";
            item.style.opacity = "";
            item.style.transform = "";
            return true;
        }

        item.style.transition = "none";
        item.style.opacity = "0";
        item.style.transform = "translateY(12px)";
        setTimeout(() => {
            item.style.transition = "opacity 0.5s ease-out, transform 0.5s ease-out";
            item.style.opacity = "1";
            item.style.transform = "translateY(0)";
        }, 10 + order * 50);
        return true;
    },

    conceal(item, animate) {
        if (item._filterState === "hidden") return;
        item._filterState = "hidden";
        clearTimeout(item._hideTimer);

        if (!animate) {
            item.classList.add("hidden");
            return;
        }

        item.style.transition = `opacity ${FADE_OUT_MS}ms ease-out, transform ${FADE_OUT_MS}ms ease-out`;
        item.style.opacity = "0";
        item.style.transform = "translateY(-8px)";
        item._hideTimer = setTimeout(() => item.classList.add("hidden"), FADE_OUT_MS);
    },

    // Filtering shrinks the page; if the reader is deep in it, bring them back to the
    // top of the (now shorter) timeline instead of leaving them stranded in a gap.
    keepPlace(animate) {
        const heading = document.getElementById("key-events");
        if (!heading) return;
        const navBottom = document.getElementById("rootNavbar")?.getBoundingClientRect().bottom ?? 0;

        if (heading.getBoundingClientRect().top < navBottom) {
            heading.scrollIntoView({ behavior: animate ? "smooth" : "auto", block: "start" });
        }
    },

    // Marks the decade (or Presidents) the reader is currently in on the jump nav.
    observeCurrentSection() {
        if (this.jumpLinks.length === 0 || typeof IntersectionObserver === "undefined") return;

        this.observer = new IntersectionObserver(
            (entries) => {
                entries.forEach((entry) => {
                    if (entry.isIntersecting) this.setCurrent(entry.target.id);
                });
            },
            { rootMargin: "-25% 0px -65% 0px" }
        );

        this.jumpLinks.forEach((link) => {
            const target = document.getElementById(link.getAttribute("data-jump"));
            if (target) this.observer.observe(target);
        });
    },

    setCurrent(id) {
        this.jumpLinks.forEach((link) => {
            if (link.getAttribute("data-jump") === id) {
                link.setAttribute("aria-current", "true");
            } else {
                link.removeAttribute("aria-current");
            }
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
        this.el.removeEventListener("click", this.onToolbarClick);
        document.removeEventListener("click", this.onTagClick);

        if (this.observer) {
            this.observer.disconnect();
            this.observer = null;
        }

        (this.timelineItems || []).forEach((item) => clearTimeout(item._hideTimer));
        (this.sections || []).forEach((section) => clearTimeout(section._hideTimer));

        this.filterButtons = null;
        this.jumpLinks = null;
        this.timelineItems = null;
        this.sections = null;
    }
};
