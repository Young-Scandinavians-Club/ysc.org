const STORAGE_KEY = "admin-media-layout";
const VALID_LAYOUTS = new Set(["square", "masonry"]);
let memoryLayout = null;

function readStoredLayout() {
    try {
        return localStorage.getItem(STORAGE_KEY);
    } catch (_error) {
        return memoryLayout;
    }
}

function writeStoredLayout(layout) {
    memoryLayout = layout;

    try {
        localStorage.setItem(STORAGE_KEY, layout);
    } catch (_error) {
        // Some privacy contexts block localStorage; the in-memory value keeps this session usable.
    }
}

let MediaLayoutPreference = {
    mounted() {
        const storedLayout = readStoredLayout();

        if (VALID_LAYOUTS.has(storedLayout)) {
            this.pushEvent("set-layout", { layout: storedLayout });
        }

        this.handleClick = (event) => {
            const button = event.target.closest("[data-media-layout]");
            if (!button || !this.el.contains(button)) return;

            const layout = button.dataset.mediaLayout;
            if (VALID_LAYOUTS.has(layout)) {
                writeStoredLayout(layout);
            }
        };

        this.el.addEventListener("click", this.handleClick);
    },

    destroyed() {
        this.el.removeEventListener("click", this.handleClick);
    },
};

export default MediaLayoutPreference;
