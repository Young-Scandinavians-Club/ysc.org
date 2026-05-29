export default StickyNavbar = {
    mounted() {
        this.isSticky = false;
        this.isMobileHidden = false;
        this.rafPending = false;
        this.lastScrollY = window.scrollY;

        this.initState();
        this.bindNavHeightObserver();
        this.syncNavHeight();

        if (this.isHeroMode) {
            this.applyHeroNavProgress(window.scrollY);
        } else if (window.scrollY >= this.stickyThreshold) {
            this.el.classList.add("nav-sticky");
            this.isSticky = true;
        }

        this.scrollHandler = () => {
            if (!this.rafPending) {
                this.rafPending = true;
                requestAnimationFrame(() => this.update());
            }
        };

        window.addEventListener("scroll", this.scrollHandler, { passive: true });

        requestAnimationFrame(() => this.update());
    },

    updated() {
        const newHeroMode = this.readHeroMode();
        if (newHeroMode !== this.isHeroMode) {
            this.el.classList.remove("nav-sticky", "nav-mobile-hidden");
            this.clearHeroNavVars();
            this.isSticky = false;
            this.isMobileHidden = false;

            requestAnimationFrame(() => {
                this.initState();
                this.syncNavHeight();
                this.update();
            });
        } else if (this.isHeroMode) {
            this.syncNavHeight();
            this.applyHeroNavProgress(window.scrollY);
            if (this.isMobileHidden && !this.el.classList.contains("nav-mobile-hidden")) {
                this.el.classList.add("nav-mobile-hidden");
            }
        } else if (this.isSticky) {
            this.syncNavHeight();
            if (!this.el.classList.contains("nav-sticky")) {
                this.el.classList.add("nav-sticky");
            }
            if (this.isMobileHidden && !this.el.classList.contains("nav-mobile-hidden")) {
                this.el.classList.add("nav-mobile-hidden");
            }
        } else {
            this.syncNavHeight();
        }
    },

    destroyed() {
        if (this.scrollHandler) {
            window.removeEventListener("scroll", this.scrollHandler);
        }
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
        }
        this.clearHeroNavVars();
    },

    bindNavHeightObserver() {
        this.resizeObserver = new ResizeObserver(() => this.syncNavHeight());
        this.resizeObserver.observe(this.el);
    },

    syncNavHeight() {
        const height = Math.ceil(this.el.getBoundingClientRect().height);
        document.documentElement.style.setProperty("--nav-height", `${height}px`);
    },

    initState() {
        this.isHeroMode = this.readHeroMode();
        this.stickyThreshold = 1;
        this.heroBgFadeEnd = 110;
        this.heroChromeFadeStart = 45;
        this.heroChromeFadeEnd = 145;
    },

    readHeroMode() {
        return (
            this.el.closest("#site-header")?.classList.contains("hero-mode") ===
            true
        );
    },

    clearHeroNavVars() {
        this.el.style.removeProperty("--hero-nav-progress");
        this.el.style.removeProperty("--hero-nav-chrome-progress");
    },

    smoothstep(t) {
        return t * t * (3 - 2 * t);
    },

    progressInRange(scrollY, start, end) {
        const t = Math.min(1, Math.max(0, (scrollY - start) / (end - start)));
        return this.smoothstep(t);
    },

    applyHeroNavProgress(scrollY) {
        const bg = this.progressInRange(scrollY, 0, this.heroBgFadeEnd);
        const chrome = this.progressInRange(
            scrollY,
            this.heroChromeFadeStart,
            this.heroChromeFadeEnd,
        );

        this.el.style.setProperty("--hero-nav-progress", bg.toFixed(4));
        this.el.style.setProperty("--hero-nav-chrome-progress", chrome.toFixed(4));
    },

    updateHeroNav(currentScrollY, delta) {
        this.applyHeroNavProgress(currentScrollY);

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
    },

    update() {
        const currentScrollY = window.scrollY;
        const delta = currentScrollY - this.lastScrollY;

        if (this.isHeroMode) {
            this.updateHeroNav(currentScrollY, delta);
            this.lastScrollY = Math.max(0, currentScrollY);
            this.rafPending = false;
            return;
        }

        if (currentScrollY >= this.stickyThreshold) {
            if (!this.isSticky) {
                this.el.classList.add("nav-sticky");
                this.isSticky = true;
            }

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
        } else if (this.isSticky) {
            this.el.classList.remove("nav-sticky", "nav-mobile-hidden");
            this.isSticky = false;
            this.isMobileHidden = false;
        }

        this.lastScrollY = Math.max(0, currentScrollY);
        this.rafPending = false;
    },
};
