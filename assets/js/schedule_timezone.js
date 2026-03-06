// ScheduleTimezone hook
// Populates the hidden timezone input with the browser's IANA timezone name
// and pre-fills the datetime-local input with a sensible default (next hour).
const ScheduleTimezone = {
    mounted() {
        const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;

        const tzInput = this.el.querySelector('input[name="timezone"]');
        if (tzInput) tzInput.value = tz;

        const tzLabel = this.el.querySelector("[data-tz-label]");
        if (tzLabel) tzLabel.textContent = tz.replace(/_/g, " ");

        const dtInput = this.el.querySelector('input[name="scheduled_at"]');
        if (dtInput && !dtInput.value) {
            const now = new Date();
            now.setMinutes(0, 0, 0);
            now.setHours(now.getHours() + 1);

            const pad = (n) => String(n).padStart(2, "0");
            dtInput.value = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`;
        }
    },
};

export default ScheduleTimezone;
