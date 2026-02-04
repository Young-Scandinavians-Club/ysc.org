/**
 * ConfirmCloseModal Hook
 *
 * Handles confirmation dialogs before closing important modals.
 * Used to prevent accidental closure of verification flows.
 */
const ConfirmCloseModal = {
  mounted() {
    // Listen for confirm_close_modal events from LiveView
    this.handleEvent("confirm_close_modal", ({ title, message, confirm_text, cancel_text, on_confirm }) => {
      // Use native browser confirmation dialog
      const confirmed = window.confirm(`${title}\n\n${message}`);

      if (confirmed) {
        // User confirmed - push the confirmation event back to LiveView
        this.pushEvent(on_confirm, {});
      }
      // If not confirmed, do nothing (stay on modal)
    });
  }
};

export default ConfirmCloseModal;
