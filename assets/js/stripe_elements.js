// Stripe Elements Hook for Phoenix LiveView
import { loadScript } from "./load_external_asset";
import { pushEventIfConnected } from "./live_view_safe_push";

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
        const publishableKey = window.stripePublishableKey ||
            document.querySelector("meta[name='stripe-publishable-key']")?.getAttribute("content");
        if (!publishableKey || publishableKey.trim() === '') {
            console.error('Stripe publishable key is not configured. Please set STRIPE_PUBLIC_KEY environment variable.');
            return null;
        }
        stripePromise = window.Stripe(publishableKey);
    }
    return stripePromise;
};

function safePushEvent(hook, event, payload = {}) {
    if (hook.isDestroyed) return;
    pushEventIfConnected(hook, event, payload);
}

function notifyStripePaymentElementLoading(hook) {
    safePushEvent(hook, 'stripe-payment-element-loading', {});
}

function notifyStripePaymentElementReady(hook) {
    safePushEvent(hook, 'stripe-payment-element-ready', {});
}

function paymentElementHasStripeContent(container) {
    return container.querySelector('.StripeElement') ||
        container.querySelector('[data-testid]') ||
        container.children.length > 0;
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

const StripeElements = {
    mounted() {
        this.loadPromise = loadScript("stripe-js", "https://js.stripe.com/v3/");
        this.isDestroyed = false;
        this.initializing = false;
        // Stable reference so removeEventListener matches across `initializeStripe` re-runs
        this._boundHandleSubmit = (e) => this.handleSubmit(e);
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
            return;
        }

        const paymentElementContainer = document.getElementById('payment-element');
        if (paymentElementContainer && paymentElementHasStripeContent(paymentElementContainer)) {
            this.showPaymentElementContainer(paymentElementContainer);
        }
    },

    showPaymentElementContainer(container) {
        if (!container) return;
        container.classList.remove('hidden');
        container.style.display = '';
    },

    async initializeStripe() {
        // Prevent multiple simultaneous initializations
        if (this.initializing) {
            return;
        }

        this.initializing = true;

        try {
            notifyStripePaymentElementLoading(this);

            const clientSecret = this.el.dataset.clientSecret;

            if (!clientSecret) {
                console.error('No client secret provided');
                return;
            }

            // Wait for the Stripe script to finish loading
            await this.loadPromise;

            if (this.isDestroyed) return;

            if (!window.Stripe) {
                console.error('Stripe not available');
                this.showMessage('Payment system not ready. Please refresh and try again.');
                return;
            }

            // If we already have this client secret initialized, don't re-initialize
            if (this.clientSecret === clientSecret && this.elements && this.paymentElement) {
                const paymentElementContainer = document.getElementById('payment-element');
                if (paymentElementContainer && document.contains(paymentElementContainer)) {
                    if (paymentElementHasStripeContent(paymentElementContainer)) {
                        this.showPaymentElementContainer(paymentElementContainer);
                        notifyStripePaymentElementReady(this);
                        return;
                    }
                }
            }

            this.clientSecret = clientSecret;

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

                this.paymentElement = this.elements.create(
                    'payment',
                    paymentElementOptions(
                        {
                            layout: 'tabs',
                            business: {
                                name: 'Young Scandinavians Club'
                            }
                        },
                        parseBillingDetails(this.el)
                    )
                );

                // Only mount if the container is still in the DOM
                if (document.contains(paymentElementContainer)) {
                    this.paymentElement.mount('#payment-element');
                    this.showPaymentElementContainer(paymentElementContainer);
                } else {
                    console.error('Payment element container is not in the DOM');
                    this.showMessage('Payment form container is not available. Please refresh and try again.');
                    return;
                }
            } else {
                // If elements already exist but payment element is not mounted, try to mount it
                if (this.paymentElement && document.contains(paymentElementContainer)) {
                    // Check if Stripe content exists in the container
                    if (!paymentElementHasStripeContent(paymentElementContainer)) {
                        try {
                            // Try to mount the payment element
                            this.paymentElement.mount('#payment-element');
                            this.showPaymentElementContainer(paymentElementContainer);
                        } catch (mountError) {
                            console.error('Failed to mount payment element:', mountError);
                            // Recreate the payment element
                            try {
                                this.paymentElement = this.elements.create('payment', {
                                    layout: 'tabs',
                                    business: {
                                        name: 'Young Scandinavians Club'
                                    }
                                });
                                this.paymentElement.mount('#payment-element');
                                this.showPaymentElementContainer(paymentElementContainer);
                            } catch (recreateError) {
                                console.error('Failed to recreate payment element:', recreateError);
                                this.showMessage('Failed to initialize payment form. Please refresh and try again.');
                                return;
                            }
                        }
                    }
                }
            }

            // Handle form submission (remove first: `initializeStripe` can run again when
            // LiveView refreshes with a new client secret, otherwise one click registers
            // multiple handlers and Stripe gets duplicate confirmPayment calls).
            const submitButton = document.getElementById('submit-payment');
            if (submitButton && this._boundHandleSubmit) {
                submitButton.removeEventListener('click', this._boundHandleSubmit);
                submitButton.addEventListener('click', this._boundHandleSubmit);
            }

            notifyStripePaymentElementReady(this);

        } catch (error) {
            console.error('Error initializing Stripe Elements:', error);
            this.showMessage('Failed to initialize payment form. Please refresh and try again.');
        } finally {
            this.initializing = false;
        }
    },

    async handleSubmit(event) {
        event.preventDefault();

        if (this._paymentConfirmInFlight) {
            return;
        }

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
        if (!paymentElementHasStripeContent(paymentElementContainer) && this.paymentElement) {
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
        } else if (!paymentElementHasStripeContent(paymentElementContainer) && !this.paymentElement) {
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

        this._paymentConfirmInFlight = true;

        try {
            // Get booking ID or ticket order ID from data attributes for redirect URL
            const bookingId = this.el.dataset.bookingId;
            const ticketOrderId = this.el.dataset.ticketOrderId;

            // Build return URL based on what we have
            let returnUrl;
            const isModification = this.el.dataset.modification === 'true';

            if (bookingId) {
                const updatedParam = isModification ? '&updated=true' : '';
                returnUrl = `${window.location.origin}/bookings/${bookingId}/receipt?confetti=true${updatedParam}`;
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
                safePushEvent(this, 'payment-redirect-started', {});
                // Give LiveView a moment to process the event before redirect happens
                // This is especially important for redirect-based payment methods (Amazon Pay, CashApp, etc.)
                await new Promise(resolve => setTimeout(resolve, 100));
            }

            if (this.isDestroyed || !this.el?.isConnected) {
                this._paymentConfirmInFlight = false;
                if (submitButton) {
                    submitButton.disabled = false;
                    submitButton.textContent = this.originalButtonText;
                }
                return;
            }

            const { error } = await this.stripe.confirmPayment({
                elements: this.elements,
                confirmParams: {
                    return_url: returnUrl,
                },
                redirect: 'if_required'
            });

            if (error) {
                const pi = error.payment_intent;
                const alreadySucceeded =
                    error.code === 'payment_intent_unexpected_state' &&
                    pi &&
                    pi.status === 'succeeded';

                if (alreadySucceeded) {
                    this.showMessage('Payment successful! Processing your order...', true);
                    safePushEvent(this, 'payment-success', {
                        payment_intent_id: pi.id || this.clientSecret.split('_secret_')[0]
                    });
                    return;
                }

                this._paymentConfirmInFlight = false;
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
                safePushEvent(this, 'payment-success', {
                    payment_intent_id: this.clientSecret.split('_secret_')[0]
                });
            }
        } catch (err) {
            console.error('Payment confirmation error:', err);
            this._paymentConfirmInFlight = false;
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
                if (!messageDiv.isConnected) return;
                messageDiv.classList.add('hidden');
            }, 5000);
        }
    },

    destroyed() {
        // Mark as destroyed to prevent any pending operations
        this.isDestroyed = true;

        // Clean up event listeners
        const submitButton = document.getElementById('submit-payment');
        if (submitButton && this._boundHandleSubmit) {
            submitButton.removeEventListener('click', this._boundHandleSubmit);
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
