// Checkout Timer Hook for Phoenix LiveView
const CheckoutTimer = {
    mounted() {
        this.initializeTimer();
    },

    updated() {
        // Re-initialize if the expires_at time changes
        const newExpiresAt = this.el.dataset.expiresAt;
        if (newExpiresAt && newExpiresAt !== this.expiresAt) {
            this.initializeTimer();
        }
    },

    initializeTimer() {
        const expiresAtString = this.el.dataset.expiresAt;

        if (!expiresAtString) {
            console.error('No expiration time provided');
            return;
        }

        // Parse the expiration time (assuming ISO format)
        this.expiresAt = new Date(expiresAtString);

        if (isNaN(this.expiresAt.getTime())) {
            console.error('Invalid expiration time format');
            return;
        }

        // Clear any existing timer
        if (this.timerInterval) {
            clearInterval(this.timerInterval);
        }

        // Start the countdown
        this.updateTimer();
        this.timerInterval = setInterval(() => {
            this.updateTimer();
        }, 1000);
    },

    updateTimer() {
        const now = new Date();
        const timeLeft = this.expiresAt.getTime() - now.getTime();

        if (timeLeft <= 0) {
            // Time has expired
            this.el.innerHTML = '<span class="text-red-600 font-bold">EXPIRED</span>';
            this.el.className = 'font-bold text-red-600';

            // Clear the timer
            if (this.timerInterval) {
                clearInterval(this.timerInterval);
            }

            // Notify the LiveView that time has expired
            this.pushEvent('checkout-expired', {});
            return;
        }

        // Calculate time components
        const minutes = Math.floor(timeLeft / (1000 * 60));
        const seconds = Math.floor((timeLeft % (1000 * 60)) / 1000);

        // Format the time display
        const timeString = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;

        // Update the display
        this.el.innerHTML = `<span class="text-blue-900">${timeString}</span>`;

        // Change color based on remaining time
        if (minutes < 2) {
            // Less than 2 minutes - show warning
            this.el.className = 'font-bold text-orange-600';
        } else if (minutes < 5) {
            // Less than 5 minutes - show caution
            this.el.className = 'font-bold text-yellow-600';
        } else {
            // More than 5 minutes - normal color
            this.el.className = 'font-bold text-blue-900';
        }
    },

    destroyed() {
        // Clean up the timer when the component is destroyed
        if (this.timerInterval) {
            clearInterval(this.timerInterval);
        }
    }
};

export default CheckoutTimer;