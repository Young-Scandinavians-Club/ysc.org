// Stripe Elements Hook for Phoenix LiveView

let stripePromise = null;

// Suppress known harmless Stripe telemetry errors (from ad blockers)
// These errors don't affect payment functionality
if (typeof window !== 'undefined' && !window.stripeErrorSuppressionInitialized) {
    window.stripeErrorSuppressionInitialized = true;

    // Suppress uncaught promise rejections for Stripe telemetry
    window.addEventListener('unhandledrejection', (event) => {
        const reason = event.reason;
        if (
            reason &&
            typeof reason === 'object' &&
            reason.message &&
            (
                reason.message.includes('r.stripe.com/b') ||
                reason.message.includes('ERR_BLOCKED_BY_CLIENT') ||
                (reason.message.includes('Failed to fetch') && reason.message.includes('stripe.com'))
            )
        ) {
            // Suppress these errors - they're from ad blockers blocking Stripe telemetry
            // Payment functionality still works fine
            event.preventDefault();
        }
    });
}

const getStripe = () => {
    if (!stripePromise && window.Stripe) {
        const publishableKey = window.stripePublishableKey;
        if (!publishableKey || publishableKey.trim() === '') {
            console.error('Stripe publishable key is not configured. Please set STRIPE_PUBLIC_KEY environment variable.');
            return null;
        }
        stripePromise = window.Stripe(publishableKey);
    }
    return stripePromise;
};

const StripeElements = {
    mounted() {
        this.isDestroyed = false;
        this.initializing = false;
        this.initializeStripe();
    },

    updated() {
        // Only re-initialize if the client secret actually changes
        // Don't re-initialize if we're already initializing or if Stripe is already working
        if (this.initializing || this.isDestroyed) {
            return;
        }

        const newClientSecret = this.el.dataset.clientSecret;

        // Only re-initialize if:
        // 1. We have a new client secret
        // 2. It's different from the current one
        // 3. We don't already have a working Stripe instance with this client secret
        if (newClientSecret &&
            newClientSecret !== this.clientSecret &&
            (!this.elements || !this.paymentElement)) {
            this.initializeStripe();
        }
    },

    async initializeStripe() {
        // Prevent multiple simultaneous initializations
        if (this.initializing) {
            return;
        }

        this.initializing = true;

        try {
            const clientSecret = this.el.dataset.clientSecret;

            if (!clientSecret) {
                console.error('No client secret provided');
                return;
            }

            // If we already have this client secret initialized, don't re-initialize
            if (this.clientSecret === clientSecret && this.elements && this.paymentElement) {
                // Just verify the element is still mounted
                const paymentElementContainer = document.getElementById('payment-element');
                if (paymentElementContainer && document.contains(paymentElementContainer)) {
                    const hasStripeContent = paymentElementContainer.querySelector('.StripeElement') ||
                        paymentElementContainer.querySelector('[data-testid]') ||
                        paymentElementContainer.children.length > 0;
                    if (hasStripeContent) {
                        // Already initialized and mounted, nothing to do
                        return;
                    }
                }
            }

            this.clientSecret = clientSecret;

            // Wait for Stripe to be available
            let attempts = 0;
            while (!window.Stripe && attempts < 50) {
                await new Promise(resolve => setTimeout(resolve, 100));
                attempts++;
            }

            if (!window.Stripe) {
                console.error('Stripe not available');
                this.showMessage('Payment system not ready. Please refresh and try again.');
                return;
            }

            const stripe = getStripe();

            if (!stripe) {
                console.error('Failed to initialize Stripe - check publishable key configuration');
                this.showMessage('Payment system not configured. Please contact support.');
                return;
            }

            this.stripe = stripe;

            // Check if payment element container exists
            const paymentElementContainer = document.getElementById('payment-element');
            if (!paymentElementContainer) {
                console.error('Payment element container not found');
                this.showMessage('Payment form container not found. Please refresh and try again.');
                return;
            }

            // Create or get the payment element
            if (!this.elements) {
                this.elements = stripe.elements({
                    clientSecret: clientSecret,
                    appearance: {
                        theme: 'stripe',
                        variables: {
                            colorPrimary: '#2563eb', // blue-600
                            colorBackground: '#ffffff',
                            colorText: '#18181b', // zinc-900
                            colorTextSecondary: '#71717a', // zinc-500
                            colorDanger: '#ef4444',
                            fontFamily: 'system-ui, -apple-system, sans-serif',
                            spacingUnit: '4px',
                            borderRadius: '12px',
                        },
                        rules: {
                            '.Input': {
                                borderRadius: '8px',
                                borderColor: '#e4e4e7',
                                padding: '12px',
                            },
                            '.Input:focus': {
                                borderColor: '#2563eb',
                                boxShadow: '0 0 0 3px rgba(37, 99, 235, 0.1)',
                            },
                            '.Label': {
                                fontWeight: '500',
                                fontSize: '14px',
                                marginBottom: '8px',
                            }
                        }
                    }
                });

                this.paymentElement = this.elements.create('payment', {
                    layout: 'tabs',
                    business: {
                        name: 'The Young Scandinavians Club'
                    }
                });

                // Only mount if the container is still in the DOM
                if (document.contains(paymentElementContainer)) {
                    this.paymentElement.mount('#payment-element');
                    // Show the payment element after mounting
                    paymentElementContainer.classList.remove('hidden');
                } else {
                    console.error('Payment element container is not in the DOM');
                    this.showMessage('Payment form container is not available. Please refresh and try again.');
                    return;
                }
            } else {
                // If elements already exist but payment element is not mounted, try to mount it
                if (this.paymentElement && document.contains(paymentElementContainer)) {
                    // Check if Stripe content exists in the container
                    const hasStripeContent = paymentElementContainer.querySelector('.StripeElement') ||
                        paymentElementContainer.querySelector('[data-testid]') ||
                        paymentElementContainer.children.length > 0;

                    if (!hasStripeContent) {
                        try {
                            // Try to mount the payment element
                            this.paymentElement.mount('#payment-element');
                            // Show the payment element after mounting
                            paymentElementContainer.classList.remove('hidden');
                        } catch (mountError) {
                            console.error('Failed to mount payment element:', mountError);
                            // Recreate the payment element
                            try {
                                this.paymentElement = this.elements.create('payment', {
                                    layout: 'tabs',
                                    business: {
                                        name: 'The Young Scandinavians Club'
                                    }
                                });
                                this.paymentElement.mount('#payment-element');
                                // Show the payment element after mounting
                                paymentElementContainer.classList.remove('hidden');
                            } catch (recreateError) {
                                console.error('Failed to recreate payment element:', recreateError);
                                this.showMessage('Failed to initialize payment form. Please refresh and try again.');
                            }
                        }
                    }
                }
            }

            // Handle form submission
            this.handleSubmit = this.handleSubmit.bind(this);
            const submitButton = document.getElementById('submit-payment');
            if (submitButton) {
                submitButton.addEventListener('click', this.handleSubmit);
            }

        } catch (error) {
            console.error('Error initializing Stripe Elements:', error);
            this.showMessage('Failed to initialize payment form. Please refresh and try again.');
        } finally {
            this.initializing = false;
        }
    },

    async handleSubmit(event) {
        event.preventDefault();

        // Check if hook is being destroyed
        if (this.isDestroyed) {
            console.warn('Payment form is being destroyed, cannot submit');
            return;
        }

        const submitButton = document.getElementById('submit-payment');
        const messageDiv = document.getElementById('payment-message');

        // Check if the hook element is still in the DOM
        if (!this.el || !document.contains(this.el)) {
            console.error('Stripe Elements hook element is not in the DOM');
            this.showMessage('Payment form is no longer available. Please refresh and try again.');
            return;
        }

        // Check if the payment element container exists
        const paymentElementContainer = document.getElementById('payment-element');
        if (!paymentElementContainer || !document.contains(paymentElementContainer)) {
            console.error('Payment element container is not in the DOM');
            this.showMessage('Payment form is no longer available. Please refresh and try again.');
            return;
        }

        if (!this.stripe || !this.paymentElement) {
            this.showMessage('Payment form not ready. Please try again.');
            return;
        }

        // Verify the payment element container exists and has Stripe content
        // Check if the payment element container has any Stripe-generated content
        const hasStripeContent = paymentElementContainer.querySelector('.StripeElement') ||
            paymentElementContainer.querySelector('[data-testid]') ||
            paymentElementContainer.children.length > 0;

        if (!hasStripeContent && this.paymentElement) {
            // Element exists but might not be mounted - try to mount it
            try {
                if (document.contains(paymentElementContainer)) {
                    this.paymentElement.mount('#payment-element');
                    // Wait a moment for the element to mount
                    await new Promise(resolve => setTimeout(resolve, 100));
                } else {
                    this.showMessage('Payment form is no longer available. Please refresh and try again.');
                    return;
                }
            } catch (mountError) {
                // If mount fails, the element might already be mounted or there's a real issue
                console.warn('Could not mount payment element, proceeding anyway:', mountError);
            }
        } else if (!hasStripeContent && !this.paymentElement) {
            // No element exists at all - this is a real problem
            this.showMessage('Payment form is not ready. Please refresh and try again.');
            return;
        }

        // Store original button text
        if (!this.originalButtonText) {
            this.originalButtonText = submitButton ? submitButton.textContent : 'Pay';
        }

        // Disable the submit button
        if (submitButton) {
            submitButton.disabled = true;
            submitButton.textContent = 'Processing...';
        }

        try {
            // Get booking ID or ticket order ID from data attributes for redirect URL
            const bookingId = this.el.dataset.bookingId;
            const ticketOrderId = this.el.dataset.ticketOrderId;

            // Build return URL based on what we have
            let returnUrl;
            if (bookingId) {
                returnUrl = `${window.location.origin}/bookings/${bookingId}/receipt?confetti=true`;
            } else if (ticketOrderId) {
                // For ticket orders, use payment success page which will redirect to order confirmation
                returnUrl = `${window.location.origin}/payment/success`;
            } else {
                returnUrl = `${window.location.origin}/payment/success`;
            }

            // Notify LiveView that a redirect might be about to happen
            // This prevents the order from being cancelled when the connection is lost
            // Send the event and wait a bit to ensure it's processed before redirect
            if (ticketOrderId || bookingId) {
                this.pushEvent('payment-redirect-started', {});
                // Give LiveView a moment to process the event before redirect happens
                // This is especially important for redirect-based payment methods (Amazon Pay, CashApp, etc.)
                await new Promise(resolve => setTimeout(resolve, 100));
            }

            const { error } = await this.stripe.confirmPayment({
                elements: this.elements,
                confirmParams: {
                    return_url: returnUrl,
                },
                redirect: 'if_required'
            });

            if (error) {
                // Show error to customer
                this.showMessage(error.message);
                if (submitButton) {
                    submitButton.disabled = false;
                    submitButton.textContent = this.originalButtonText;
                }
            } else {
                // Payment succeeded
                this.showMessage('Payment successful! Processing your order...', true);

                // Notify the LiveView that payment was successful
                this.pushEvent('payment-success', {
                    payment_intent_id: this.clientSecret.split('_secret_')[0]
                });
            }
        } catch (err) {
            console.error('Payment confirmation error:', err);
            this.showMessage('An unexpected error occurred. Please try again.');
            if (submitButton) {
                submitButton.disabled = false;
                submitButton.textContent = this.originalButtonText;
            }
        }
    },

    showMessage(message, isSuccess = false) {
        const messageDiv = document.getElementById('payment-message');
        if (messageDiv) {
            messageDiv.textContent = message;
            messageDiv.classList.remove('hidden');

            // Update styling based on message type
            if (isSuccess) {
                messageDiv.className = 'text-sm text-green-600 font-medium';
            } else {
                messageDiv.className = 'text-sm text-red-600';
            }

            // Hide message after 5 seconds
            setTimeout(() => {
                messageDiv.classList.add('hidden');
            }, 5000);
        }
    },

    destroyed() {
        // Mark as destroyed to prevent any pending operations
        this.isDestroyed = true;

        // Clean up event listeners
        const submitButton = document.getElementById('submit-payment');
        if (submitButton && this.handleSubmit) {
            submitButton.removeEventListener('click', this.handleSubmit);
        }

        // Unmount Stripe Elements
        if (this.paymentElement) {
            try {
                // Check if element is still in DOM before unmounting
                const paymentElementContainer = document.getElementById('payment-element');
                if (paymentElementContainer && document.contains(paymentElementContainer)) {
                    this.paymentElement.unmount();
                }
            } catch (e) {
                // Element might already be unmounted, ignore error
                console.warn('Error unmounting Stripe payment element:', e);
            }
            this.paymentElement = null;
        }

        // Clean up references
        this.elements = null;
        this.stripe = null;
        this.clientSecret = null;
    }
};

export default StripeElements;