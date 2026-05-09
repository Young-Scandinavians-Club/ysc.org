/**
 * ClipboardCopy Hook
 *
 * Provides copy-to-clipboard functionality with visual feedback
 *
 * Usage:
 *   <button phx-hook="ClipboardCopy" data-copy="text to copy">
 *   <button phx-hook="ClipboardCopy" data-copy-target="input-id">
 *     <.icon name="hero-clipboard" />
 *   </button>
 */
export default {
    mounted() {
        this.el.addEventListener("click", (e) => {
            e.preventDefault();

            const textToCopy = this.textToCopy();
            if (!textToCopy) return;

            this.copyText(textToCopy)
                .then(() => this.showSuccess())
                .catch((err) => {
                    console.error("Failed to copy to clipboard:", err);
                    this.showFailure();
                });
        });
    },

    textToCopy() {
        const targetId = this.el.getAttribute("data-copy-target");
        const target = targetId ? document.getElementById(targetId) : null;

        if (target) {
            return "value" in target ? target.value : target.textContent;
        }

        return this.el.getAttribute("data-copy");
    },

    copyText(text) {
        if (navigator.clipboard && window.isSecureContext) {
            return navigator.clipboard.writeText(text);
        }

        return this.copyTextFallback(text);
    },

    copyTextFallback(text) {
        return new Promise((resolve, reject) => {
            const textArea = document.createElement("textarea");
            textArea.value = text;
            textArea.setAttribute("readonly", "");
            textArea.style.position = "fixed";
            textArea.style.top = "-9999px";
            textArea.style.left = "-9999px";
            document.body.appendChild(textArea);
            textArea.select();

            try {
                if (document.execCommand("copy")) {
                    resolve();
                } else {
                    reject(new Error("document.execCommand('copy') returned false"));
                }
            } catch (err) {
                reject(err);
            } finally {
                document.body.removeChild(textArea);
            }
        });
    },

    showSuccess() {
        this.showFeedback("Copied");
        this.el.classList.add("bg-green-50", "border-green-500", "text-green-700");
        this.el.classList.remove("border-zinc-300", "hover:border-zinc-400", "hover:bg-zinc-50");

        window.clearTimeout(this.resetTimeout);
        this.resetTimeout = window.setTimeout(() => this.resetFeedback(), 1500);
    },

    showFailure() {
        this.showFeedback("Copy failed");
        this.el.classList.remove(
            "border-zinc-300",
            "hover:border-zinc-400",
            "hover:bg-zinc-50",
            "bg-green-50",
            "border-green-500",
            "text-green-700",
            "hover:bg-green-50",
            "hover:border-green-600"
        );
        this.el.classList.add("bg-red-50", "border-red-500", "text-red-700");

        window.clearTimeout(this.resetTimeout);
        this.resetTimeout = window.setTimeout(() => this.resetFeedback(), 2000);
    },

    showFeedback(message) {
        const feedback = this.feedbackElement();
        if (!feedback) return;

        const label = feedback.querySelector("[data-copy-feedback-label]");
        if (label) label.textContent = message;

        feedback.classList.remove("hidden");
        feedback.classList.add("inline-flex");
    },

    resetFeedback() {
        const feedback = this.feedbackElement();

        if (feedback) {
            feedback.classList.add("hidden");
            feedback.classList.remove("inline-flex");
        }

        this.el.classList.remove(
            "bg-green-50",
            "border-green-500",
            "text-green-700",
            "bg-red-50",
            "border-red-500",
            "text-red-700"
        );
        this.el.classList.add("border-zinc-300", "hover:border-zinc-400", "hover:bg-zinc-50");
    },

    feedbackElement() {
        const feedbackId = this.el.getAttribute("data-copy-feedback");
        return feedbackId ? document.getElementById(feedbackId) : null;
    },
};
