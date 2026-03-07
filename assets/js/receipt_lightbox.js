// Receipt Lightbox Hook - uses GLightbox for image previews in expense reports
import { loadScript, loadStylesheet } from "./load_external_asset";

const ReceiptLightbox = {
    mounted() {
        loadStylesheet("glightbox-css", "https://unpkg.com/glightbox/dist/css/glightbox.min.css");
        loadScript("glightbox-js", "https://unpkg.com/glightbox/dist/js/glightbox.min.js");
        this.initializeLightbox();
    },

    updated() {
        // Re-initialize when content is updated by LiveView
        this.initializeLightbox();
    },

    initializeLightbox() {
        // Wait for GLightbox to be available (it's loaded with defer)
        if (typeof GLightbox === 'undefined') {
            setTimeout(() => this.initializeLightbox(), 100);
            return;
        }

        // Find the lightbox link within this element
        const link = this.el.querySelector('a[data-lightbox="receipt"]');

        if (!link) return;

        // Use a unique gallery name based on the element ID to avoid conflicts
        const galleryName = `receipt-${this.el.id}`;

        // Skip if already initialized with this gallery
        if (link.dataset.gallery === galleryName) return;

        link.classList.add('glightbox');
        link.setAttribute('data-gallery', galleryName);
        // Set the type to image explicitly
        link.setAttribute('data-type', 'image');

        // Destroy existing instance if it exists
        if (this.lightboxInstance) {
            this.lightboxInstance.destroy();
        }

        // Create new instance using the elements array approach for better control
        this.lightboxInstance = GLightbox({
            elements: [{
                href: link.getAttribute('href'),
                type: 'image',
            }],
            touchNavigation: true,
            closeButton: true,
            openEffect: 'fade',
            closeEffect: 'fade',
        });

        // Manually handle click to open the lightbox
        link.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();
            if (this.lightboxInstance) {
                this.lightboxInstance.open();
            }
        });
    },

    destroyed() {
        if (this.lightboxInstance) {
            this.lightboxInstance.destroy();
            this.lightboxInstance = null;
        }
    }
};

export default ReceiptLightbox;