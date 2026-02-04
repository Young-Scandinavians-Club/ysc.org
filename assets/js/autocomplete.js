/**
 * Autocomplete Hook
 *
 * Provides keyboard navigation (arrow keys, enter, escape) for the autocomplete component.
 * Also handles click-outside to close the dropdown.
 */
const Autocomplete = {
    mounted() {
        this.selectedIndex = -1;
        this.lastResultCount = 0;
        this.boundHandleKeydown = this.handleKeydown.bind(this);
        this.bindInput();

        // Close dropdown when clicking outside
        this.handleClickOutside = (e) => {
            if (!this.el.contains(e.target)) {
                this.clearSelection();
            }
        };
        document.addEventListener("click", this.handleClickOutside);
    },

    destroyed() {
        document.removeEventListener("click", this.handleClickOutside);
        if (this.input) {
            this.input.removeEventListener("keydown", this.boundHandleKeydown);
        }
    },

    updated() {
        // Re-bind input after updates (it may have been added/removed)
        this.bindInput();

        const results = this.getResultButtons();
        const currentCount = results.length;

        // Only reset selection if results changed (new search)
        if (currentCount !== this.lastResultCount) {
            this.selectedIndex = -1;
            this.lastResultCount = currentCount;
        }

        // Ensure visual state matches
        this.updateSelection();
    },

    bindInput() {
        const newInput = this.el.querySelector("input[type='text']");

        // If input changed, rebind event listener
        if (newInput !== this.input) {
            // Remove old listener if exists
            if (this.input) {
                this.input.removeEventListener("keydown", this.boundHandleKeydown);
            }

            this.input = newInput;

            // Add new listener if input exists
            if (this.input) {
                this.input.addEventListener("keydown", this.boundHandleKeydown);
            }
        }
    },

    handleKeydown(e) {
        const results = this.getResultButtons();

        // Only handle navigation keys if we have results
        if (results.length === 0) {
            return;
        }

        switch (e.key) {
            case "ArrowDown":
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                this.selectedIndex = Math.min(
                    this.selectedIndex + 1,
                    results.length - 1
                );
                this.updateSelection();
                return false;

            case "ArrowUp":
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                if (this.selectedIndex <= 0) {
                    this.selectedIndex = 0;
                } else {
                    this.selectedIndex--;
                }
                this.updateSelection();
                return false;

            case "Enter":
                if (this.selectedIndex >= 0 && results[this.selectedIndex]) {
                    e.preventDefault();
                    e.stopPropagation();
                    results[this.selectedIndex].click();
                    this.selectedIndex = -1;
                }
                break;

            case "Escape":
                e.preventDefault();
                this.clearSelection();
                this.input.blur();
                break;

            case "Tab":
                // Select current item if one is highlighted, otherwise let tab work normally
                if (this.selectedIndex >= 0 && results[this.selectedIndex]) {
                    e.preventDefault();
                    results[this.selectedIndex].click();
                    this.selectedIndex = -1;
                }
                break;
        }
    },

    getResultButtons() {
        return Array.from(this.el.querySelectorAll("ul button"));
    },

    updateSelection() {
        const results = this.getResultButtons();
        results.forEach((btn, index) => {
            if (index === this.selectedIndex) {
                btn.classList.add("bg-zinc-100");
                btn.classList.add("text-zinc-900");
                // Scroll into view if needed
                btn.scrollIntoView({ block: "nearest", behavior: "smooth" });
            } else {
                btn.classList.remove("bg-zinc-100");
                btn.classList.remove("text-zinc-900");
            }
        });
    },

    clearSelection() {
        this.selectedIndex = -1;
        this.updateSelection();
    },
};

export default Autocomplete;