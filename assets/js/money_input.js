import { pushEventIfConnected } from "./live_view_safe_push";

let MoneyInput = {
    mounted() {
        const input = this.el;
        const hook = this;
        this._debounceTimer = null;

        const pushValue = (value) => {
            const tierId =
                input.getAttribute("data-tier-id") ||
                input.getAttribute("phx-value-tier-id") ||
                input.closest("[data-tier-id]")?.getAttribute("data-tier-id");

            // Only push event if this is a donation input (has data-tier-id)
            // Regular price inputs in admin forms should not trigger this event
            if (!tierId) {
                return;
            }

            const name = input.getAttribute("name");

            // Get the value without formatting (remove commas)
            const cleanValue = value.replace(/,/g, "");

            // Build the event payload with the input name as a dynamic key
            const eventPayload = {
                "tier-id": tierId
            };
            eventPayload[name] = cleanValue;

            pushEventIfConnected(hook, "update-donation-amount", eventPayload);
        };

        const debouncedPush = (value) => {
            clearTimeout(this._debounceTimer);
            this._debounceTimer = setTimeout(() => pushValue(value), 300);
        };

        input.addEventListener("input", (e) => {
            let value = e.target.value.replace(/[^\d.]/g, "");

            const decimalPoints = value.match(/\./g);
            if (decimalPoints && decimalPoints.length > 1) {
                const parts = value.split(".");
                value = parts[0] + "." + parts.slice(1).join("");
            }

            const parts = value.split(".");
            if (parts[1] && parts[1].length > 2) {
                parts[1] = parts[1].substring(0, 2);
                value = parts.join(".");
            }

            if (parts[0].length > 3) {
                parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
                value = parts.join(".");
            }

            e.target.value = value;

            debouncedPush(value);
        });

        input.addEventListener("focus", (e) => {
            const value = e.target.value.replace(/,/g, "");
            e.target.value = value;
        });

        input.addEventListener("blur", (e) => {
            if (e.target.value) {
                const num = parseFloat(e.target.value.replace(/,/g, ""));
                if (!isNaN(num)) {
                    const parts = num.toFixed(2).split(".");
                    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
                    e.target.value = parts.join(".");
                    pushValue(e.target.value);
                }
            } else {
                pushValue("");
            }
        });
    },

    destroyed() {
        if (this._debounceTimer) {
            clearTimeout(this._debounceTimer);
            this._debounceTimer = null;
        }
    }
};

export default MoneyInput;
