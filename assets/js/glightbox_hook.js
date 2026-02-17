// GLightbox Hook for Trix images and inline image links in Phoenix LiveView
const IMAGE_EXTENSIONS = /\.(jpe?g|png|gif|webp|avif|svg)(\?|$)/i;

const GLightboxHook = {
    mounted() {
        this.initializeLightbox();
    },

    updated() {
        this.initializeLightbox();
    },

    initializeLightbox() {
        if (typeof GLightbox === 'undefined') {
            setTimeout(() => this.initializeLightbox(), 100);
            return;
        }

        // Collect lightbox-ready elements from both Trix figures and plain image links
        const elements = [];
        const clickTargets = [];

        // 1) Trix figures: figure.attachment[data-trix-attachment] > a > img
        this.el.querySelectorAll('figure.attachment[data-trix-attachment]').forEach((fig) => {
            const link = fig.querySelector('a[href]');
            const img = fig.querySelector('img');
            if (!link || !img) return;

            const cap = fig.querySelector('figcaption')?.textContent?.trim() || '';
            const entry = { href: link.getAttribute('href'), type: 'image' };
            if (cap) entry.title = cap;

            elements.push(entry);
            clickTargets.push(link);
        });

        // 2) Plain inline image links: a[href] > img (not inside a Trix figure)
        this.el.querySelectorAll('a[href]').forEach((link) => {
            const img = link.querySelector('img');
            if (!img) return;
            if (link.closest('figure.attachment[data-trix-attachment]')) return;
            if (link.dataset.glightboxReady) return;

            const href = link.getAttribute('href');
            const src = img.getAttribute('src');
            if (!IMAGE_EXTENSIONS.test(href) && !IMAGE_EXTENSIONS.test(src)) return;

            // Extract caption text from siblings of the img inside the link
            const caption = extractCaption(link, img);

            // Restructure DOM for nicer presentation
            restructureImageLink(link, img, caption);

            // Clean URL (strip download disposition) for both the link and lightbox
            const cleanHref = href.replace(/[?&]content-disposition=[^&]*/i, '');
            link.setAttribute('href', cleanHref);

            const entry = { href: cleanHref, type: 'image' };
            if (caption) entry.title = caption;

            elements.push(entry);
            clickTargets.push(link);

            link.dataset.glightboxReady = 'true';
        });

        if (elements.length === 0) return;

        // Tear down previous instance
        if (this.lightboxInstance) {
            this.lightboxInstance.destroy();
        }

        // Build a single GLightbox with the collected elements
        this.lightboxInstance = GLightbox({
            elements: elements,
            touchNavigation: true,
            closeButton: true,
            openEffect: 'fade',
            closeEffect: 'fade',
        });

        // Bind click handlers so each image opens the lightbox at its index
        const lb = this.lightboxInstance;
        clickTargets.forEach((target, index) => {
            // Remove old handler if re-initializing
            if (target._glightboxHandler) {
                target.removeEventListener('click', target._glightboxHandler);
            }
            const handler = (e) => {
                e.preventDefault();
                e.stopPropagation();
                lb.openAt(index);
            };
            target._glightboxHandler = handler;
            target.addEventListener('click', handler);
        });
    },

    destroyed() {
        if (this.lightboxInstance) {
            this.lightboxInstance.destroy();
            this.lightboxInstance = null;
        }
    }
};

function extractCaption(link, img) {
    let caption = '';
    for (const node of link.childNodes) {
        if (node === img) continue;
        if (node.nodeType === Node.TEXT_NODE) {
            caption += node.textContent;
        } else if (node.nodeType === Node.ELEMENT_NODE && node.tagName !== 'IMG') {
            caption += node.textContent;
        }
    }
    return caption.trim();
}

function restructureImageLink(link, img, caption) {
    // Remove all child nodes that aren't the img (text captions, etc.)
    const toRemove = [];
    for (const node of link.childNodes) {
        if (node !== img) toRemove.push(node);
    }
    toRemove.forEach(n => n.remove());

    // Wrap the link in a figure-like container
    const wrapper = document.createElement('figure');
    wrapper.className = 'post-render-image-figure';
    link.parentNode.insertBefore(wrapper, link);
    wrapper.appendChild(link);

    // Add styled caption below the image if present
    if (caption) {
        const captionEl = document.createElement('figcaption');
        captionEl.className = 'post-render-caption';
        captionEl.textContent = caption;
        wrapper.appendChild(captionEl);
    }
}

module.exports = GLightboxHook;
