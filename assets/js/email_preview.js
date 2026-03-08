const EmailPreview = {
    scrollContainer() {
        return document.getElementById("preview-scroll-container");
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

    writeToIframe(html) {
        try {
            const doc =
                this.el.contentDocument || this.el.contentWindow.document;
            doc.open();
            doc.write(html);
            doc.close();
        } catch (_e) {}
    },

    async renderPreview(html) {
        const container = this.scrollContainer();
        const scrollPos = container ? container.scrollTop : 0;
        const lockedHeight = this.el.offsetHeight;

        this.el.style.transition = "opacity 0.1s ease";
        this.el.style.opacity = "0.4";

        this.writeToIframe(html);
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

        this.el.style.transition = "opacity 0.15s ease";
        this.el.style.opacity = "1";
    },

    mounted() {
        this.handleEvent("preview-html", ({ html }) => {
            if (html) this.renderPreview(html);
        });
    },
};

export default EmailPreview;
