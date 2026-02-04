let MoneyInput = {
    mounted() {
        const input = this.el;
        const hook = this;

        // Debounce timer
        let debounceTimer = null;

        // Push value to LiveView (only for donation inputs)
        const pushValue = (value) => {
        const tierId = input.getAttribute("data-tier-id") ||
            input.getAttribute("phx-value-tier-id") ||
            input.closest("[data-tier-id]")?.getAttribute("data-tier-id");

            // Only push event if this is a donation input (has data-tier-id)
            // Regular price inputs in admin forms should not trigger this event
            if (!tierId) {
                return;
            }

            const name = input.getAttribute("name");

            // Get the value without formatting (remove commas)ke
            const cleanValue = value.replace(/,/g, "");

            // Build the event payload with the input name as a dynamic key
            const eventPayload = {
                "tier-id": tierId
            };
            eventPayload[name] = cleanValue;

            // Push to LiveView with the input name and tier-id
            hook.pushEvent("update-donation-amount", eventPayload);
        };

        // Debounced push function
        const debouncedPush = (value) => {
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(() => pushValue(value), 300);
        };

        // Handle input changes
        input.addEventListener("input", (e) => {
            // Remove any non-numeric characters except decimal point
            let value = e.target.value.replace(/[^\d.]/g, "");

            // Ensure only one decimal point
            const decimalPoints = value.match(/\./g);
            if (decimalPoints && decimalPoints.length > 1) {
                const parts = value.split(".");
                value = parts[0] + "." + parts.slice(1).join("");
            }

            // Limit to two decimal places
            const parts = value.split(".");
            if (parts[1] && parts[1].length > 2) {
                parts[1] = parts[1].substring(0, 2);
                value = parts.join(".");
            }

            // Optional: Format with thousand separators as user types
            // Only format the part before the decimal
            if (parts[0].length > 3) {
                parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
                value = parts.join(".");
            }

            e.target.value = value;

            // Push value to LiveView (debounced)
            debouncedPush(value);
        });

        // Remove formatting when focusing
        input.addEventListener("focus", (e) => {
            const value = e.target.value.replace(/,/g, "");
            e.target.value = value;
        });

        // Reapply formatting when leaving field
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
};

export default MoneyInput;
