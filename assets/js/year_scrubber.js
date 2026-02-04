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
        // Update year sections when content changes
        this.updateYearSections();
        this.handleScroll();

        // If there's a pending scroll, try to execute it now that DOM is updated
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
        // Find all year section headings in the document
        this.yearSections = Array.from(
            document.querySelectorAll('[data-year-section]')
        ).map(section => {
            const year = section.getAttribute('data-year-section');
            const heading = section.querySelector('h2');
            return {
                year: parseInt(year),
                element: section,
                heading: heading
            };
        });

        // Sort by year descending
        this.yearSections.sort((a, b) => b.year - a.year);
    },

    handleScroll() {
        // Skip if we're programmatically scrolling
        if (this.isScrolling) return;

        // Debounce scroll events
        if (this.scrollTimeout) {
            clearTimeout(this.scrollTimeout);
        }

        this.scrollTimeout = setTimeout(() => {
            if (this.yearSections.length === 0) {
                this.updateYearSections();
                if (this.yearSections.length === 0) return;
            }

            const scrollTop = window.scrollY || document.documentElement.scrollTop;
            const viewportHeight = window.innerHeight;
            const scrollPosition = scrollTop + viewportHeight * 0.2; // Highlight when 20% from top

            // Find the current year section
            let activeYear = null;
            for (let i = 0; i < this.yearSections.length; i++) {
                const section = this.yearSections[i];
                const rect = section.element.getBoundingClientRect();
                const elementTop = rect.top + scrollTop;

                if (scrollPosition >= elementTop) {
                    activeYear = section.year;
                    break;
                }
            }

            // If no section found, use the last one (oldest year)
            if (activeYear === null && this.yearSections.length > 0) {
                activeYear = this.yearSections[this.yearSections.length - 1].year;
            }

            // Update highlight if year changed
            if (activeYear !== null && activeYear !== this.currentYear) {
                this.currentYear = activeYear;
                this.updateHighlight();
            }
        }, 100);
    },

    updateHighlight() {
        // Remove highlight from all items
        const items = this.scrubber.querySelectorAll('[data-year-item]');
        items.forEach(item => {
            item.classList.remove('active', 'bg-blue-500', 'text-white', 'opacity-100');
            item.classList.add('opacity-60');
        });

        // Add highlight to current year
        if (this.currentYear !== null) {
            const activeItem = this.scrubber.querySelector(
                `[data-year-item="${this.currentYear}"]`
            );
            if (activeItem) {
                activeItem.classList.add('active', 'bg-blue-500', 'text-white', 'opacity-100');
                activeItem.classList.remove('opacity-60');
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

        // Reset scrolling flag after animation
        setTimeout(() => {
            this.isScrolling = false;
        }, 1000);
    }
};

export default YearScrubber;