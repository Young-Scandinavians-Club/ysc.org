let AdminSearch = {
    mounted() {
        this.input = this.el.querySelector('input[type="search"]');
        this.resultsContainer = this.el.querySelector('[data-results-container]');
        this.selectedIndex = -1;
        this.resultItems = [];

        // Bind keyboard event handler
        this.handleKeyDown = this.handleKeyDown.bind(this);
        if (this.input) {
            this.input.addEventListener('keydown', this.handleKeyDown);
        }
    },

    updated() {
        // Update result items when results change
        this.resultsContainer = this.el.querySelector('[data-results-container]');
        if (this.resultsContainer) {
            this.resultItems = Array.from(
                this.resultsContainer.querySelectorAll('a[data-result-item]')
            );
            // Reset selection when results update
            this.selectedIndex = -1;
            this.updateSelection();
        } else {
            // Results container not visible, reset
            this.resultItems = [];
            this.selectedIndex = -1;
        }
    },

    destroyed() {
        if (this.input) {
            this.input.removeEventListener('keydown', this.handleKeyDown);
        }
    },

    handleKeyDown(e) {
        // Update results container reference in case it changed
        this.resultsContainer = this.el.querySelector('[data-results-container]');

        if (!this.resultsContainer || !this.resultsContainer.offsetParent) {
            // Results not visible, ignore
            return;
        }

        // Update result items in case they changed
        this.resultItems = Array.from(
            this.resultsContainer.querySelectorAll('a[data-result-item]')
        );

        if (this.resultItems.length === 0) {
            return;
        }

        const { key } = e;

        if (key === 'ArrowDown') {
            e.preventDefault();
            this.selectedIndex = Math.min(
                this.selectedIndex + 1,
                this.resultItems.length - 1
            );
            this.updateSelection();
            this.scrollToSelected();
        } else if (key === 'ArrowUp') {
            e.preventDefault();
            this.selectedIndex = Math.max(this.selectedIndex - 1, -1);
            this.updateSelection();
            this.scrollToSelected();
        } else if (key === 'Enter') {
            e.preventDefault();
            // If no item is selected, select the first one
            const indexToSelect = this.selectedIndex >= 0 ? this.selectedIndex : 0;
            if (this.resultItems[indexToSelect]) {
                const selectedItem = this.resultItems[indexToSelect];
                const href = selectedItem.getAttribute('href');
                if (href) {
                    window.location.href = href;
                }
            }
        } else if (key === 'Escape') {
            // Close results on escape
            this.pushEvent('close_results', {});
        }
    },

    updateSelection() {
        this.resultItems.forEach((item, index) => {
            if (index === this.selectedIndex) {
                item.classList.add('bg-blue-50', 'ring-2', 'ring-blue-500');
                item.classList.remove('hover:bg-zinc-50');
            } else {
                item.classList.remove('bg-blue-50', 'ring-2', 'ring-blue-500');
                item.classList.add('hover:bg-zinc-50');
            }
        });
    },

    scrollToSelected() {
        if (this.selectedIndex >= 0 && this.resultItems[this.selectedIndex]) {
            const selectedItem = this.resultItems[this.selectedIndex];
            selectedItem.scrollIntoView({
                behavior: 'smooth',
                block: 'nearest'
            });
        }
    }
};

export default AdminSearch;