import { loadScript } from "./load_external_asset";
import { pushEventIfConnected } from "./live_view_safe_push";

function safePushEvent(hook, event, payload = {}) {
    if (hook._destroyed) return;
    pushEventIfConnected(hook, event, payload);
}

function parseBillingDetails(el) {
    const raw = el?.dataset?.billingDetails;
    if (!raw || raw.trim() === '') return null;

    try {
        const parsed = JSON.parse(raw);
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
            return null;
        }
        return Object.keys(parsed).length > 0 ? parsed : null;
    } catch (e) {
        console.warn('Failed to parse Stripe billing details', e);
        return null;
    }
}

function paymentElementOptions(baseOptions, billingDetails) {
    if (!billingDetails) return baseOptions;
    return {
        ...baseOptions,
        defaultValues: {
            billingDetails,
        },
    };
}

let StripeInput = {
    mounted() {
        this._destroyed = false;
        this._paymentElement = null;
        this._elements = null;
        this._stripe = null;

        this._onPaymentChange = (event) => {
            if (this._destroyed) return;
            const submitButton = document.getElementById("submit");
            const cardErrors = document.getElementById("card-errors");
            if (!submitButton || !cardErrors) return;

            if (event.error) {
                cardErrors.textContent = event.error.message;
                submitButton.disabled = true;
            } else {
                cardErrors.textContent = "";
                submitButton.disabled = false;
            }
        };

        this._onSubmit = async (event) => {
            event.preventDefault();
            if (this._destroyed || !this.el.isConnected) return;

            const submitButton = document.getElementById("submit");
            const cardErrors = document.getElementById("card-errors");
            if (!submitButton || !cardErrors || !this._stripe || !this._elements) return;

            let submitted = false;

            try {
                cardErrors.textContent = "";
                submitButton.disabled = true;
                submitButton.classList.add("phx-submit-loading");

                const returnURL = this.el.dataset.returnurl;

                const { error, setupIntent } = await this._stripe.confirmSetup({
                    elements: this._elements,
                    redirect: "if_required",
                    confirmParams: {
                        return_url: returnURL,
                    },
                });

                if (this._destroyed || !this.el.isConnected) {
                    submitted = true;
                    return;
                }

                if (error) {
                    console.error(error);
                    cardErrors.textContent = error.message;
                    return;
                }

                safePushEvent(this, "payment-method-set", {
                    payment_method_id: setupIntent.payment_method,
                });
                submitted = true;
            } finally {
                if (!submitted && submitButton && !this._destroyed && this.el.isConnected) {
                    submitButton.disabled = false;
                    submitButton.classList.remove("phx-submit-loading");
                }
            }
        };

        this.loadPromise = loadScript("stripe-js", "https://js.stripe.com/v3/");
        this.initializeStripe();
    },

    async initializeStripe() {
        try {
            await this.loadPromise;
        } catch (e) {
            console.error("Stripe failed to load:", e);
            return;
        }

        if (this._destroyed || !this.el.isConnected) return;

        if (!window.Stripe) {
            console.error("Stripe not available");
            return;
        }

        const clientSecret = this.el.dataset.clientsecret;
        const publishableKey =
            this.el.dataset.publickey ||
            document.querySelector("meta[name='stripe-publishable-key']")?.getAttribute("content");

        const stripe = Stripe(publishableKey);

        const appearance = {};
        const options = paymentElementOptions(
            { layout: "accordion" },
            parseBillingDetails(this.el)
        );
        const elements = stripe.elements({ clientSecret, appearance });
        const paymentElement = elements.create("payment", options);
        paymentElement.mount("#payment-element");

        if (this._destroyed || !this.el.isConnected) {
            try {
                paymentElement.unmount();
            } catch (_) {}
            return;
        }

        this._stripe = stripe;
        this._elements = elements;
        this._paymentElement = paymentElement;

        paymentElement.on("change", this._onPaymentChange);
        this.el.addEventListener("submit", this._onSubmit);
    },

    destroyed() {
        this._destroyed = true;
        this.el.removeEventListener("submit", this._onSubmit);

        if (this._paymentElement) {
            try {
                this._paymentElement.unmount();
            } catch (_) {}
            this._paymentElement = null;
        }

        this._elements = null;
        this._stripe = null;
    },
};

export default StripeInput;
