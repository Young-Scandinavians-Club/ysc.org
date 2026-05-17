// Resend Timer Hook - handles countdown timers for resend buttons
import { pushEventIfConnected } from "./live_view_safe_push";

function formatResendCodeWait(seconds) {
    const n = Number(seconds);
    if (!Number.isFinite(n) || n <= 0) {
        return "";
    }
    const unit = n === 1 ? "second" : "seconds";
    return `You can resend the code in ${n} ${unit}.`;
}

export default {
    mounted() {
        this.interval = setInterval(() => {
            if (!this.el?.isConnected) {
                if (this.interval) clearInterval(this.interval);
                return;
            }

            const countdownElements = this.el.querySelectorAll('[data-countdown]');

            if (countdownElements.length > 0) {
                countdownElements.forEach(element => {
                    const countdownValue = element.dataset.countdown;
                    const remaining = parseInt(countdownValue, 10);

                    if (isNaN(remaining) || remaining <= 0) {
                        const timerType = element.dataset.timerType || 'unknown';
                        element.removeAttribute('data-countdown');
                        element.style.display = 'none';
                        pushEventIfConnected(this, 'resend_timer_expired', { type: timerType });
                        return;
                    }

                    if (remaining > 1) {
                        element.dataset.countdown = remaining - 1;
                        element.textContent = formatResendCodeWait(remaining - 1);
                    } else {
                        const timerType = element.dataset.timerType || 'unknown';
                        element.removeAttribute('data-countdown');
                        element.style.display = 'none';
                        pushEventIfConnected(this, 'resend_timer_expired', { type: timerType });
                    }
                });
            }
        }, 1000);
    },

    destroyed() {
        if (this.interval) {
            clearInterval(this.interval);
        }
    }
};
