export default StickyNavbar = {
    mounted() {
        this.isSticky = false;
        this.isMobileHidden = false;
        this.rafPending = false;
        this.lastScrollY = window.scrollY;

        this.scrollHandler = () => {
            if (!this.rafPending) {
                this.rafPending = true;
                requestAnimationFrame(() => this.update());
            }
        };

        window.addEventListener("scroll", this.scrollHandler, { passive: true });

        // Defer the initial check so the browser has finished layout and
        // offsetHeight / getBoundingClientRect() are accurate.
        requestAnimationFrame(() => {
            this.initState();
            this.update();
        });
    },

    // Called by LiveView when the element's attributes are patched (SPA navigation).
    // The closure in mounted() is stale after navigation, so we re-read hero mode here.
    updated() {
        const newHeroMode = this.el.dataset.heroMode === "true";
        if (newHeroMode !== this.isHeroMode) {
            // Hero mode changed — fully reset before re-initialising.
            this.el.classList.remove("nav-sticky", "nav-mobile-hidden");
            document.body.style.paddingTop = "0px";
            this.isSticky = false;
            this.isMobileHidden = false;

            requestAnimationFrame(() => {
                this.initState();
                this.update();
            });
        }
    },

    destroyed() {
        if (this.scrollHandler) {
            window.removeEventListener("scroll", this.scrollHandler);
        }
        document.body.style.paddingTop = "0px";
    },

    // ---- helpers ----

    initState() {
        this.isHeroMode = this.el.dataset.heroMode === "true";

        // Both modes use a small positive threshold so the nav appears in its
        // natural, non-elevated state when the user is exactly at the top
        // (scrollY = 0).
        //
        // Hero pages  – header is position:absolute, no flow offset; 10 px gives
        //               a grace zone while the hero is still in view.
        // Normal pages – nav is at the top of the document (flow offset ~= 0);
        //               1 px is enough to trigger sticky without a perceptible
        //               content jump, and lets scrollY = 0 show the plain header.
        this.stickyThreshold = this.isHeroMode ? 10 : 1;
    },

    update() {
        const currentScrollY = window.scrollY;
        const delta = currentScrollY - this.lastScrollY;

        if (currentScrollY >= this.stickyThreshold) {
            // ---- make sticky ----
            if (!this.isSticky) {
                // Set body padding BEFORE fixing the nav so content doesn't jump.
                // Hero pages skip this: their header is position:absolute and
                // doesn't occupy space in the normal flow.
                if (!this.isHeroMode) {
                    document.body.style.paddingTop = this.el.offsetHeight + "px";
                }

                this.el.classList.add("nav-sticky");
                this.isSticky = true;
            }

            // ---- mobile: hide on scroll-down, reveal on scroll-up ----
            // Require a minimum delta to avoid toggling on tiny/bouncy scrolls.
            // Skip hiding until past 80 px so the hero→sticky transition settles.
            if (window.innerWidth < 1024) {
                if (delta > 4 && currentScrollY > 80) {
                    if (!this.isMobileHidden) {
                        this.el.classList.add("nav-mobile-hidden");
                        this.isMobileHidden = true;
                    }
                } else if (delta < -4) {
                    if (this.isMobileHidden) {
                        this.el.classList.remove("nav-mobile-hidden");
                        this.isMobileHidden = false;
                    }
                }
            }
        } else {
            // ---- make unsticky ----
            if (this.isSticky) {
                this.el.classList.remove("nav-sticky", "nav-mobile-hidden");
                document.body.style.paddingTop = "0px";
                this.isSticky = false;
                this.isMobileHidden = false;
            }
        }

        this.lastScrollY = Math.max(0, currentScrollY);
        this.rafPending = false;
    },
};
