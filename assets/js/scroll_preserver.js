let ScrollPreserver = {
    mounted() {
        this.gallery = this.el;
        this.savedScrollPosition = null;
        this.isModalOpen = false;

        // Listen for modal show events
        // The modal uses phx-mounted with show_modal, which triggers when modal opens
        this.handleModalShow = () => {
            if (!this.isModalOpen) {
                // Capture scroll position before modal opens
                this.savedScrollPosition = window.scrollY || document.documentElement.scrollTop;
                this.isModalOpen = true;
                console.debug('ScrollPreserver: Captured scroll position:', this.savedScrollPosition);
            }
        };

        // Listen for modal hide events
        // The modal uses phx-remove with hide_modal, which triggers when modal closes
        this.handleModalHide = () => {
            if (this.isModalOpen && this.savedScrollPosition !== null) {
                this.isModalOpen = false;
                // Restore scroll position after modal closes
                // Use requestAnimationFrame to ensure DOM is ready
                requestAnimationFrame(() => {
                    window.scrollTo({
                        top: this.savedScrollPosition,
                        behavior: 'auto'
                    });
                    console.debug('ScrollPreserver: Restored scroll position:', this.savedScrollPosition);
                    this.savedScrollPosition = null;
                });
            }
        };

        // Listen for modal element appearing (when phx-mounted fires)
        // We'll observe the modal element itself
        const modalObserver = new MutationObserver((mutations) => {
            mutations.forEach((mutation) => {
                mutation.addedNodes.forEach((node) => {
                    if (node.nodeType === 1 && node.id === 'update-image-modal') {
                        // Modal is being added to DOM
                        this.handleModalShow();
                    }
                });
                mutation.removedNodes.forEach((node) => {
                    if (node.nodeType === 1 && node.id === 'update-image-modal') {
                        // Modal is being removed from DOM
                        this.handleModalHide();
                    }
                });
            });
        });

        // Observe the document body for modal additions/removals
        modalObserver.observe(document.body, {
            childList: true,
            subtree: true
        });

        this.modalObserver = modalObserver;

        // Also listen for phx:show and phx:hide events if they're dispatched
        window.addEventListener('phx:show', (e) => {
            if (e.target && e.target.id === 'update-image-modal') {
                this.handleModalShow();
            }
        });

        window.addEventListener('phx:hide', (e) => {
            if (e.target && e.target.id === 'update-image-modal') {
                this.handleModalHide();
            }
        });
    },

    destroyed() {
        // Clean up observers and event listeners
        if (this.modalObserver) {
            this.modalObserver.disconnect();
        }
        window.removeEventListener('phx:show', this.handleModalShow);
        window.removeEventListener('phx:hide', this.handleModalHide);
    },

    updated() {
        // Check if modal state changed by looking for the modal element
        const modal = document.getElementById('update-image-modal');
        const modalIsVisible = modal && !modal.classList.contains('hidden');

        if (modalIsVisible && !this.isModalOpen) {
            // Modal just opened
            this.handleModalShow();
        } else if (!modalIsVisible && this.isModalOpen) {
            // Modal just closed
            this.handleModalHide();
        }
    }
};

export default ScrollPreserver;