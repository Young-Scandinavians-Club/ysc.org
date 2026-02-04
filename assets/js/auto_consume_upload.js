// Auto-consume upload hook for expense reports
// Automatically consumes the upload when it's done (entry.done? && progress == 100)
let AutoConsumeUpload = {
    mounted() {
        this.checkAndConsume();
        // Poll every 300ms to check if upload is done
        this.intervalId = setInterval(() => this.checkAndConsume(), 300);
    },

    updated() {
        this.checkAndConsume();
    },

    destroyed() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
        }
    },

    checkAndConsume() {
        const ref = this.el.dataset.ref;
        const uploadType = this.el.dataset.uploadType || 'receipt';

        // Find the consume button
        const consumeButton = document.getElementById(`${uploadType}-consume-${ref}`);
        if (!consumeButton) return;

        // Check if button is enabled (which means entry.done? && progress == 100)
        const isDone = consumeButton.dataset.done === 'true' &&
                       parseInt(consumeButton.dataset.progress) === 100;
        const isDisabled = consumeButton.disabled;

        // If done and not disabled and not already consumed, auto-click
        if (isDone && !isDisabled && !this.consumed) {
            this.consumed = true;
            if (this.intervalId) {
                clearInterval(this.intervalId);
                this.intervalId = null;
            }
            // Small delay to ensure everything is ready
            setTimeout(() => {
                consumeButton.click();
            }, 100);
        }
    }
};

export default AutoConsumeUpload;

