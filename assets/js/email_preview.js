const EmailPreview = {
    scrollContainer() {
        return this.el.closest("#preview-scroll-container");
    },

    resize(minHeight = 0) {
        try {
            const doc =
                this.el.contentDocument || this.el.contentWindow.document;
            if (!doc || !doc.body) return;
            const measured = Math.max(
                doc.body.scrollHeight,
                doc.body.offsetHeight
            );
            const height = Math.max(measured, minHeight);
            if (height > 0) this.el.style.height = `${height}px`;
        } catch (_e) {}
    },

    waitForImages(doc) {
        const pending = Array.from(doc.getElementsByTagName("img")).filter(
            (img) => !img.complete
        );
        if (pending.length === 0) return Promise.resolve();
        return Promise.all(
            pending.map(
                (img) =>
                    new Promise((resolve) => {
                        img.addEventListener("load", resolve, { once: true });
                        img.addEventListener("error", resolve, { once: true });
                    })
            )
        );
    },

    async resizeAfterLoad() {
        const container = this.scrollContainer();
        const scrollPos = container ? container.scrollTop : 0;
        const lockedHeight = this.el.offsetHeight;

        this.resize(lockedHeight);

        if (container && scrollPos > 0) {
            container.scrollTop = scrollPos;
        }

        try {
            const doc =
                this.el.contentDocument || this.el.contentWindow.document;
            await this.waitForImages(doc);
        } catch (_e) {}

        this.resize();

        if (container && scrollPos > 0) {
            container.scrollTop = scrollPos;
        }
    },

    mounted() {
        this.handleLoad = () => this.resizeAfterLoad();
        this.el.addEventListener("load", this.handleLoad);

        // The initial srcdoc can finish loading before LiveView mounts the hook.
        this.resizeAfterLoad();
    },

    updated() {
        this.resizeAfterLoad();
    },

    destroyed() {
        this.el.removeEventListener("load", this.handleLoad);
    },
};

export default EmailPreview;
