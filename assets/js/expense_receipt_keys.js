// Arrow-key navigation for the admin expense-report receipt viewer.
// Clicks the existing prev/next buttons so navigation uses the same
// LiveView events as the on-screen controls.
const ExpenseReceiptKeys = {
    mounted() {
        this.handler = (event) => {
            if (
                event.key !== "ArrowLeft" &&
                event.key !== "ArrowRight" &&
                event.key !== "ArrowUp" &&
                event.key !== "ArrowDown"
            ) {
                return;
            }

            const active = document.activeElement;
            const tag = active && active.tagName;

            if (tag === "INPUT" || tag === "SELECT" || tag === "TEXTAREA") {
                return;
            }

            if (active && active.isContentEditable) {
                return;
            }

            const next =
                event.key === "ArrowRight" || event.key === "ArrowDown";
            const button = this.el.querySelector(
                next ? "#expense-receipt-next" : "#expense-receipt-prev"
            );

            if (!button) {
                return;
            }

            event.preventDefault();
            event.stopPropagation();
            button.click();
        };

        window.addEventListener("keydown", this.handler, true);
    },

    destroyed() {
        if (this.handler) {
            window.removeEventListener("keydown", this.handler, true);
            this.handler = null;
        }
    },
};

export default ExpenseReceiptKeys;
