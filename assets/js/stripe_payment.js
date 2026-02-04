let StripeInput = {
    mounted() {
        const clientSecret = this.el.dataset.clientsecret;
        const stripe = Stripe(this.el.dataset.publickey);

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

        this.el.addEventListener("submit", async(event) => {
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