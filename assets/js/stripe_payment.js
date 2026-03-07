import { loadScript } from "./load_external_asset";

let StripeInput = {
    mounted() {
        loadScript("stripe-js", "https://js.stripe.com/v3/");
        this.initializeStripe();
    },

    async initializeStripe() {
        // Wait for the Stripe script injected by loadScript to finish loading
        let attempts = 0;
        while (!window.Stripe && attempts < 50) {
            await new Promise(resolve => setTimeout(resolve, 100));
            attempts++;
        }

        if (!window.Stripe) {
            console.error("Stripe failed to load");
            return;
        }

        const clientSecret = this.el.dataset.clientsecret;
        const publishableKey = this.el.dataset.publickey ||
            document.querySelector("meta[name='stripe-publishable-key']")?.getAttribute("content");

        const stripe = Stripe(publishableKey);

        const appearance = {};
        const options = { layout: "accordion" };
        const elements = stripe.elements({ clientSecret, appearance });
        const paymentElement = elements.create("payment", options);
        paymentElement.mount("#payment-element");

        const returnURL = this.el.dataset.returnurl;

        const submitButton = document.getElementById("submit");
        const cardErrors = document.getElementById("card-errors");

        paymentElement.on("change", function(event) {
            if (event.error) {
                cardErrors.textContent = event.error.message;
                submitButton.disabled = true;
            } else {
                cardErrors.textContent = "";
                submitButton.disabled = false;
            }
        });

        this.el.addEventListener("submit", async (event) => {
            event.preventDefault();

            try {
                cardErrors.textContent = "";
                submitButton.disabled = true;
                submitButton.classList.add("phx-submit-loading");

                const { error, setupIntent } = await stripe.confirmSetup({
                    elements,
                    redirect: "if_required",
                    confirmParams: {
                        return_url: returnURL,
                    },
                });

                if (error) {
                    console.error(error);
                    cardErrors.textContent = error.message;
                    return;
                }

                this.pushEvent("payment-method-set", {
                    payment_method_id: setupIntent.payment_method,
                });
            } finally {
                submitButton.disabled = false;
                submitButton.classList.remove("phx-submit-loading");
            }
        });
    },
};

export default StripeInput;
