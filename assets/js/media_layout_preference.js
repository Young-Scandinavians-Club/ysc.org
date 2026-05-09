const STORAGE_KEY = "admin-media-layout";
const VALID_LAYOUTS = new Set(["square", "masonry"]);

let MediaLayoutPreference = {
    mounted() {
        const storedLayout = localStorage.getItem(STORAGE_KEY);

        if (VALID_LAYOUTS.has(storedLayout)) {
            this.pushEvent("set-layout", { layout: storedLayout });
        }

        this.handleClick = (event) => {
            const button = event.target.closest("[data-media-layout]");
            if (!button || !this.el.contains(button)) return;

            const layout = button.dataset.mediaLayout;
            if (VALID_LAYOUTS.has(layout)) {
                localStorage.setItem(STORAGE_KEY, layout);
            }
        };

        this.el.addEventListener("click", this.handleClick);
    },

    destroyed() {
        this.el.removeEventListener("click", this.handleClick);
    },
};

export default MediaLayoutPreference;
