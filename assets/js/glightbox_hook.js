// GLightbox Hook for Trix images in Phoenix LiveView
const GLightboxHook = {
    mounted() {
        this.initializeLightbox();
    },

    updated() {
        // Re-initialize when content is updated by LiveView
        this.initializeLightbox();
    },

    initializeLightbox() {
        // Wait for GLightbox to be available (it's loaded with defer)
        if (typeof GLightbox === 'undefined') {
            // If GLightbox isn't loaded yet, wait a bit and try again
            setTimeout(() => this.initializeLightbox(), 100);
            return;
        }

        // Find all Trix figures that wrap an <a><img/></a>
        const figures = this.el.querySelectorAll('figure.attachment[data-trix-attachment]');

        figures.forEach((fig) => {
            const link = fig.querySelector('a[href]');
            const img = fig.querySelector('img');
            const cap = fig.querySelector('figcaption')?.textContent?.trim() || '';

            if (!link || !img) return;

            // Skip if already initialized
            if (link.classList.contains('glightbox')) return;

            // Group all images into one gallery
            link.classList.add('glightbox');
            link.setAttribute('data-gallery', 'trix');

            // Use caption as the lightbox title/description
            if (cap) {
                link.setAttribute('data-title', cap);
            }

            // Optional: extract width/height from Trix's metadata (helps with layout)
            const raw = fig.getAttribute('data-trix-attachment');
            if (raw) {
                try {
                    const meta = JSON.parse(raw.replace(/&quot;/g, '"'));
                    if (meta.width && meta.height) {
                        link.setAttribute('data-width', meta.width);
                        link.setAttribute('data-height', meta.height);
                    }
                } catch (_) {
                    // Ignore parsing errors
                }
            }
        });

        // Initialize GLightbox if we have any images
        if (figures.length > 0) {
            // Destroy existing instance if it exists
            if (this.lightboxInstance) {
                this.lightboxInstance.destroy();
            }

            // Create new instance
            this.lightboxInstance = GLightbox({ selector: '.glightbox' });
        }
    },

    destroyed() {
        // Clean up GLightbox instance when component is destroyed
        if (this.lightboxInstance) {
            this.lightboxInstance.destroy();
            this.lightboxInstance = null;
        }
    }
};

module.exports = GLightboxHook;