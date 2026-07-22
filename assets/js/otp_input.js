// OTP input hook — distributes pasted/autofilled codes across digit boxes.
// Intercepts paste via beforeinput (capture) so maxlength=1 does not truncate.

function normalizeDigits(text) {
    // Ignore leading/trailing whitespace and any other non-digits (e.g. " 123456 ", "123 456").
    return (text || "").trim().replace(/\D/g, "");
}

function dispatchInput(input) {
    input.dispatchEvent(new Event("input", { bubbles: true }));
}

function dispatchChange(input) {
    input.dispatchEvent(new Event("change", { bubbles: true }));
}

export default {
    mounted() {
        this.getInputs = () => this.el.querySelectorAll("[data-otp-input-item]");

        this.handleBeforeInput = (event) => {
            if (!event.target.matches("[data-otp-input-item]")) return;

            const isPaste =
                event.inputType === "insertFromPaste" ||
                event.inputType === "insertReplacementText" ||
                (event.inputType === "insertText" && event.data && event.data.length > 1);

            if (isPaste) {
                event.preventDefault();
                this.fillInputs(event.data || "");
            }
        };

        this.handlePaste = (event) => {
            if (!event.target.matches("[data-otp-input-item]")) return;

            event.preventDefault();
            const paste = event.clipboardData?.getData("text") || "";
            this.fillInputs(paste);
        };

        this.handleInput = (event) => {
            const input = event.target;
            if (!input.matches("[data-otp-input-item]")) return;

            const inputs = this.getInputs();
            const index = Array.from(inputs).indexOf(input);
            const digits = normalizeDigits(input.value);

            if (digits.length > 1) {
                this.fillInputs(digits, index);
                return;
            }

            const digit = digits.slice(0, 1);
            if (input.value !== digit) {
                input.value = digit;
                dispatchInput(input);
            }

            if (digit && index < inputs.length - 1) {
                inputs[index + 1].focus();
            }
        };

        this.handleKeydown = (event) => {
            const input = event.target;
            if (!input.matches("[data-otp-input-item]")) return;

            const inputs = this.getInputs();
            const index = Array.from(inputs).indexOf(input);

            if (event.key === "Backspace") {
                if (!input.value && index > 0) {
                    event.preventDefault();
                    inputs[index - 1].focus();
                    inputs[index - 1].value = "";
                    dispatchInput(inputs[index - 1]);
                }
            } else if (event.key === "ArrowLeft" && index > 0) {
                inputs[index - 1].focus();
            } else if (event.key === "ArrowRight" && index < inputs.length - 1) {
                inputs[index + 1].focus();
            }
        };

        this.el.addEventListener("beforeinput", this.handleBeforeInput, true);
        this.el.addEventListener("paste", this.handlePaste, true);
        this.el.addEventListener("input", this.handleInput);
        this.el.addEventListener("keydown", this.handleKeydown);
    },

    destroyed() {
        this.el.removeEventListener("beforeinput", this.handleBeforeInput, true);
        this.el.removeEventListener("paste", this.handlePaste, true);
        this.el.removeEventListener("input", this.handleInput);
        this.el.removeEventListener("keydown", this.handleKeydown);
    },

    fillInputs(text, startIndex = 0) {
        const digits = normalizeDigits(text);
        const inputs = this.getInputs();

        if (startIndex === 0) {
            for (const input of inputs) {
                input.value = "";
            }
        }

        const filledCount = Math.min(digits.length, inputs.length - startIndex);

        for (let i = 0; i < filledCount; i++) {
            inputs[startIndex + i].value = digits[i];
            dispatchInput(inputs[startIndex + i]);
        }

        for (let i = startIndex + filledCount; i < inputs.length; i++) {
            inputs[i].value = "";
            dispatchInput(inputs[i]);
        }

        if (filledCount > 0) {
            const lastIndex = startIndex + filledCount - 1;
            dispatchChange(inputs[lastIndex]);

            if (lastIndex < inputs.length - 1) {
                inputs[lastIndex + 1].focus();
            } else {
                inputs[lastIndex].focus();
            }
        }
    },
};
