let ScrollToSection = {
    mounted() {
        this.handleScroll();
    },

    updated() {
        this.handleScroll();
    },

    handleScroll() {
        // Check both data-section attribute and URL hash
        const sectionId = this.el.getAttribute("data-section") ||
            (window.location.hash ? window.location.hash.substring(1) : null);
        if (!sectionId) return;

        // Wait for DOM to be ready
        setTimeout(() => {
            const element = document.getElementById(sectionId);
            if (element) {
                // Switch to the correct tab if needed
                const tabMap = {
                    "general-information": "general",
                    "cabin-rules": "rules",
                    "booking-rules": "rules",
                    "bear-safety": "rules",
                    "cancellation-policy": "rules",
                    "door-code-access": "general",
                    "getting-there": "general",
                    "parking-transportation": "general"
                };

                const targetTab = tabMap[sectionId];
                if (targetTab) {
                    // Trigger tab switch if needed
                    const currentTab = document.querySelector('button[phx-value-tab="' + targetTab + '"]');
                    if (currentTab && !currentTab.classList.contains("border-blue-600")) {
                        currentTab.click();
                        // Wait for tab to switch before scrolling
                        setTimeout(() => {
                            this.scrollToElement(element);
                        }, 300);
                    } else {
                        this.scrollToElement(element);
                    }
                } else {
                    this.scrollToElement(element);
                }
            }
        }, 200);
    },

    scrollToElement(element) {
        // Open details element if it's inside one
        const details = element.closest("details");
        if (details && !details.hasAttribute("open")) {
            details.setAttribute("open", "");
            // Wait a bit for details to open
            setTimeout(() => {
                this.performScroll(element);
            }, 100);
        } else {
            this.performScroll(element);
        }
    },

    performScroll(element) {
        // Calculate offset for fixed header
        const headerOffset = 100;
        const elementPosition = element.getBoundingClientRect().top;
        const offsetPosition = elementPosition + window.pageYOffset - headerOffset;

        window.scrollTo({
            top: offsetPosition,
            behavior: "smooth"
        });
    }
};

export default ScrollToSection;