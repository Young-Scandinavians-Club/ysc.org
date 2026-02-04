const EmailPreview = {
    mounted() {
        const iframe = this.el;
        if (!iframe) return;

        // Set up iframe to display email content
        // The srcdoc attribute is already set in the template
        // We can adjust height based on content if needed
        iframe.onload = () => {
            try {
                // Try to get the content height and adjust iframe
                const iframeDoc = iframe.contentDocument || iframe.contentWindow.document;
                if (iframeDoc && iframeDoc.body) {
                    const height = Math.max(
                        iframeDoc.body.scrollHeight,
                        iframeDoc.body.offsetHeight,
                        iframeDoc.documentElement.clientHeight,
                        iframeDoc.documentElement.scrollHeight,
                        iframeDoc.documentElement.offsetHeight
                    );
                    // Set a reasonable max height but allow scrolling
                    iframe.style.height = `${Math.min(height + 20, 800)}px`;
                }
            } catch (e) {
                // Cross-origin or other security restrictions - use default height
                console.log("EmailPreview: Could not access iframe content", e);
            }
        };
    },

    updated() {
        // Re-run mounted logic if the iframe content changes
        this.mounted();
    },
};

export default EmailPreview;