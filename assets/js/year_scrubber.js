let YearScrubber = {
    mounted() {
        this.scrubber = this.el;
        this.gallery = document.getElementById('media-gallery');
        this.yearSections = [];
        this.currentYear = null;
        this.scrollTimeout = null;
        this.isScrolling = false;
        this.pendingScrollYear = null;

        // Bind event handlers
        this.handleScroll = this.handleScroll.bind(this);
        this.handleScrubberClick = this.handleScrubberClick.bind(this);
        this.handleScrollToYear = this.handleScrollToYear.bind(this);

        // Set up scroll listener
        window.addEventListener('scroll', this.handleScroll, { passive: true });

        // Set up scrubber click handlers
        this.scrubber.addEventListener('click', this.handleScrubberClick);

        // Listen for scroll-to-year events from LiveView
        this.handleEvent('scroll-to-year', this.handleScrollToYear);

        // Initialize year sections and highlight
        this.updateYearSections();
        this.handleScroll();
    },

    updated() {
        this.updateYearSections();

        // Re-apply the current highlight immediately — LiveView may have re-rendered
        // the scrubber buttons with their static base classes, wiping the hook's state.
        if (this.currentYear !== null) {
            this.updateHighlight();
        }

        this.handleScroll();

        if (this.pendingScrollYear) {
            setTimeout(() => {
                this.updateYearSections();
                if (this.pendingScrollYear) {
                    this.scrollToYear(this.pendingScrollYear);
                    this.pendingScrollYear = null;
                }
            }, 100);
        }
    },

    destroyed() {
        window.removeEventListener('scroll', this.handleScroll);
        this.scrubber.removeEventListener('click', this.handleScrubberClick);
    },

    handleScrollToYear({ year }) {
        // Scroll to year after DOM updates
        this.pendingScrollYear = year;
        // Force immediate update check
        setTimeout(() => {
            this.updateYearSections();
            if (this.pendingScrollYear) {
                this.scrollToYear(this.pendingScrollYear);
                this.pendingScrollYear = null;
            }
        }, 50);
    },

    updateYearSections() {
        this.yearSections = Array.from(
            document.querySelectorAll('[data-year-section]')
        ).map(section => ({
            year: parseInt(section.getAttribute('data-year-section')),
            element: section
        }));

        this.yearSections.sort((a, b) => b.year - a.year);
    },

    handleScroll() {
        if (this.isScrolling) return;

        if (this.scrollTimeout) clearTimeout(this.scrollTimeout);

        this.scrollTimeout = setTimeout(() => {
            if (this.yearSections.length === 0) {
                this.updateYearSections();
                if (this.yearSections.length === 0) return;
            }

            // The section headers are `position: sticky`, so getBoundingClientRect().top
            // is always 0 once stuck — useless for determining scroll position.
            // Instead, use offsetTop (distance to offsetParent = the grid) which is
            // the natural layout position, unaffected by stickiness.
            const grid = document.getElementById('images-grid');
            if (!grid) return;

            const scrollY = window.scrollY || document.documentElement.scrollTop;
            // Document-level top of the grid (stable; not affected by sticky children).
            const gridDocumentTop = grid.getBoundingClientRect().top + scrollY;
            const scrollPosition = scrollY + window.innerHeight * 0.2;

            let activeYear = null;
            for (let i = 0; i < this.yearSections.length; i++) {
                const section = this.yearSections[i];
                const naturalTop = gridDocumentTop + section.element.offsetTop;
                if (scrollPosition >= naturalTop) {
                    activeYear = section.year;
                    break;
                }
            }

            if (activeYear === null && this.yearSections.length > 0) {
                activeYear = this.yearSections[this.yearSections.length - 1].year;
            }

            if (activeYear !== null) {
                this.currentYear = activeYear;
                this.updateHighlight();
            }
        }, 100);
    },

    updateHighlight() {
        const items = this.scrubber.querySelectorAll('[data-year-item]');
        items.forEach(item => {
            item.classList.remove('bg-zinc-800', 'text-white', 'opacity-100');
            item.classList.add('text-zinc-600', 'opacity-60');
        });

        if (this.currentYear !== null) {
            const activeItem = this.scrubber.querySelector(
                `[data-year-item="${this.currentYear}"]`
            );
            if (activeItem) {
                activeItem.classList.remove('text-zinc-600', 'opacity-60');
                activeItem.classList.add('bg-zinc-800', 'text-white', 'opacity-100');
            }
        }
    },

    handleScrubberClick(e) {
        const yearItem = e.target.closest('[data-year-item]');
        if (!yearItem) return;

        // Prevent default button behavior - LiveView will handle the click via phx-click
        // The button already has phx-click="jump-to-year" so we don't need to do anything here
        // Just let the LiveView handle it
    },

    scrollToYear(year) {
        const section = this.yearSections.find(s => s.year === year);
        if (!section) {
            // Try again after a short delay in case DOM hasn't updated
            setTimeout(() => {
                this.updateYearSections();
                const retrySection = this.yearSections.find(s => s.year === year);
                if (retrySection) {
                    this.scrollToYear(year);
                }
            }, 100);
            return;
        }

        this.isScrolling = true;

        // Scroll to the section
        const rect = section.element.getBoundingClientRect();
        const scrollTop = window.scrollY || document.documentElement.scrollTop;
        const targetY = rect.top + scrollTop - 100; // 100px offset from top

        window.scrollTo({
            top: targetY,
            behavior: 'smooth'
        });

        // Reset scrolling flag after animation completes (~500ms) then force a
        // scroll detection so the highlight reflects the final resting position.
        setTimeout(() => {
            this.isScrolling = false;
            this.handleScroll();
        }, 600);
    }
};

export default YearScrubber;