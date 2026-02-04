// LocalTime Hook for Phoenix LiveView
// Converts UTC timestamps to browser local time
const LocalTime = {
    mounted() {
        this.updateTime();
    },

    updated() {
        this.updateTime();
    },

    updateTime() {
        const utcTimeString = this.el.dataset.utcTime;
        const prefix = this.el.dataset.prefix || "";

        if (!utcTimeString) {
            return;
        }

        try {
            // Parse the UTC time string
            const utcDate = new Date(utcTimeString);

            if (isNaN(utcDate.getTime())) {
                console.error('Invalid UTC time format:', utcTimeString);
                return;
            }

            // Format the date in local timezone
            const options = {
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit',
                timeZoneName: 'short'
            };

            const localTimeString = utcDate.toLocaleString(undefined, options);

            // Update the element's text content
            this.el.textContent = prefix + localTimeString;
        } catch (error) {
            console.error('Error converting UTC time to local time:', error);
        }
    }
};

export default LocalTime;

