// LocalTime Hook for Phoenix LiveView
// Converts UTC timestamps to browser local time, falling back to America/Los_Angeles (PST/PDT).
const LocalTime = {
    mounted() { this.updateTime(); },
    updated() { this.updateTime(); },

    updateTime() {
        const utcTimeString = this.el.dataset.utcTime;
        if (!utcTimeString) return;

        try {
            const utcDate = new Date(utcTimeString);
            if (isNaN(utcDate.getTime())) return;

            // Detect the browser timezone; fall back to Pacific time.
            let timeZone;
            try {
                timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "America/Los_Angeles";
            } catch (_) {
                timeZone = "America/Los_Angeles";
            }

            const datePart = utcDate.toLocaleDateString("en-US", {
                year: "numeric", month: "long", day: "numeric", timeZone,
            });
            const timePart = utcDate.toLocaleTimeString("en-US", {
                hour: "numeric", minute: "2-digit", timeZoneName: "short", timeZone,
            });

            this.el.textContent = `${datePart} at ${timePart}`;
        } catch (error) {
            // Leave the server-rendered fallback text untouched on any error.
        }
    }
};

export default LocalTime;

