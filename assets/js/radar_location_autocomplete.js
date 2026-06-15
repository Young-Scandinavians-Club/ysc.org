import { loadScript } from "./load_external_asset";
import { pushEventIfConnected } from "./live_view_safe_push";

/** Radar Web SDK core bundle — shared with RadarMap hook. */
const RADAR_VERSION = "5.1.0";

const NEAR = { latitude: 37.7749, longitude: -122.4194 };
const MIN_QUERY_LENGTH = 2;
const DEBOUNCE_MS = 200;

const INPUT_CLASS =
    "block w-full pl-10 rounded-md text-zinc-900 border border-zinc-300 shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm";

function radarPublicKey() {
    if (!window.radarPublicKey) {
        window.radarPublicKey = document
            .querySelector("meta[name='radar-public-key']")
            ?.getAttribute("content");
    }

    return (
        window.radarPublicKey ||
        "prj_test_pk_5bcfd56661bb7fc596d70d5f21f0e2c6049b0966"
    );
}

function parsePresets(el) {
    const raw = el.dataset.presets;

    if (!raw) return [];

    try {
        const parsed = JSON.parse(raw);
        return Array.isArray(parsed) ? parsed : [];
    } catch {
        return [];
    }
}

function locationNameFromResult(result) {
    return result.placeLabel || result.addressLabel || result.label || result.location_name || "";
}

function normalizePreset(preset) {
    return {
        source: "preset",
        label: preset.label,
        location_name: preset.location_name || preset.label,
        address: preset.address || "",
        latitude: preset.latitude,
        longitude: preset.longitude,
        place_id: null,
        subtitle: preset.address || "",
    };
}

function normalizeRadarAddress(address) {
    return {
        source: "radar",
        label: locationNameFromResult(address),
        location_name: locationNameFromResult(address),
        address: address.formattedAddress || "",
        latitude: address.latitude,
        longitude: address.longitude,
        place_id: address.placeId || null,
        subtitle: address.formattedAddress || "",
    };
}

function matchesQuery(text, query) {
    return text.toLowerCase().includes(query.toLowerCase());
}

function filterPresets(presets, query) {
    if (!query) return presets.map(normalizePreset);

    return presets
        .filter(
            (preset) =>
                matchesQuery(preset.label || "", query) ||
                matchesQuery(preset.location_name || "", query) ||
                matchesQuery(preset.address || "", query),
        )
        .map(normalizePreset);
}

function pushLocationSelected(hook, result) {
    pushEventIfConnected(hook, "location-selected", {
        location_name: result.location_name || result.label || "",
        address: result.address || "",
        latitude: result.latitude,
        longitude: result.longitude,
        place_id: result.place_id || null,
    });
}

export default RadarLocationAutocomplete = {
    async mounted() {
        this._active = true;
        this._presets = parsePresets(this.el);
        this._selectedIndex = -1;
        this._results = [];
        this._searchToken = 0;

        this.el.classList.add("relative");

        this.el.innerHTML = `
            <label for="event-location-search-input" class="sr-only">Search Venue</label>
            <div class="relative mt-2">
                <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                    <span class="hero-magnifying-glass w-5 h-5 text-zinc-400" aria-hidden="true"></span>
                </div>
                <input
                    id="event-location-search-input"
                    type="text"
                    autocomplete="off"
                    placeholder="Search for a venue or address..."
                    class="${INPUT_CLASS}"
                />
            </div>
            <ul
                id="event-location-search-results"
                class="hidden absolute z-20 mt-1 w-full bg-white border border-zinc-200 rounded shadow-lg max-h-60 overflow-auto pt-2"
                role="listbox"
            ></ul>
        `;

        this.input = this.el.querySelector("#event-location-search-input");
        this.resultsList = this.el.querySelector("#event-location-search-results");

        this.boundHandleInput = this.handleInput.bind(this);
        this.boundHandleKeydown = this.handleKeydown.bind(this);
        this.boundHandleClickOutside = this.handleClickOutside.bind(this);
        this.boundHandleFocus = this.handleFocus.bind(this);

        this.input.addEventListener("input", this.boundHandleInput);
        this.input.addEventListener("keydown", this.boundHandleKeydown);
        this.input.addEventListener("focus", this.boundHandleFocus);
        document.addEventListener("click", this.boundHandleClickOutside);

        try {
            await loadScript(
                "radar-js",
                `https://js.radar.com/v${RADAR_VERSION}/radar.min.js`,
            );
        } catch (e) {
            console.error("Radar failed to load:", e);
            return;
        }

        if (!window.Radar || typeof window.Radar.initialize !== "function") {
            console.error("Radar SDK is missing or failed to initialize.");
            return;
        }

        window.Radar.initialize(radarPublicKey());
    },

    destroyed() {
        this._active = false;

        if (this.input) {
            this.input.removeEventListener("input", this.boundHandleInput);
            this.input.removeEventListener("keydown", this.boundHandleKeydown);
            this.input.removeEventListener("focus", this.boundHandleFocus);
        }

        document.removeEventListener("click", this.boundHandleClickOutside);
        clearTimeout(this._debounceTimer);
    },

    handleFocus() {
        const query = this.input.value.trim();
        this.refreshResults(query, true);
    },

    handleInput() {
        clearTimeout(this._debounceTimer);

        this._debounceTimer = setTimeout(() => {
            if (!this._active) return;
            this.refreshResults(this.input.value.trim(), true);
        }, DEBOUNCE_MS);
    },

    async refreshResults(query, openDropdown) {
        const token = ++this._searchToken;
        const presetResults = filterPresets(this._presets, query);
        let radarResults = [];

        if (query.length >= MIN_QUERY_LENGTH && window.Radar?.autocomplete) {
            try {
                const response = await window.Radar.autocomplete({
                    query,
                    near: NEAR,
                    countryCode: "US",
                    layers: ["place", "address"],
                    limit: 8,
                });

                if (token !== this._searchToken) return;

                radarResults = (response?.addresses || []).map(normalizeRadarAddress);
            } catch (error) {
                console.error("Radar autocomplete failed:", error);
            }
        }

        if (token !== this._searchToken) return;

        const presetIds = new Set(presetResults.map((result) => result.label.toLowerCase()));

        const dedupedRadarResults = radarResults.filter((result) => {
            const key = (result.label || "").toLowerCase();
            return key && !presetIds.has(key);
        });

        this._results = [...presetResults, ...dedupedRadarResults];
        this._selectedIndex = -1;
        this.renderResults(openDropdown);
    },

    renderResults(openDropdown) {
        this.resultsList.innerHTML = "";

        if (this._results.length === 0) {
            this.resultsList.classList.add("hidden");
            return;
        }

        const presetResults = this._results.filter((result) => result.source === "preset");
        const radarResults = this._results.filter((result) => result.source === "radar");
        let index = 0;

        const appendHeading = (text, withBorder) => {
            const heading = document.createElement("li");
            heading.className = [
                "px-3 py-1 text-xs font-semibold text-zinc-500 uppercase tracking-wide",
                withBorder ? "border-t border-zinc-100" : "",
            ]
                .filter(Boolean)
                .join(" ");
            heading.textContent = text;
            heading.setAttribute("aria-hidden", "true");
            this.resultsList.appendChild(heading);
        };

        const appendResultButton = (result) => {
            const currentIndex = index++;
            const item = document.createElement("li");
            const button = document.createElement("button");

            button.type = "button";
            button.className =
                "w-full text-left px-3 py-2 text-sm text-zinc-800 hover:bg-zinc-50 focus:bg-zinc-50 focus:outline-none";
            button.setAttribute("role", "option");
            button.dataset.index = String(currentIndex);

            const title = document.createElement("div");
            title.className = "font-medium";
            title.textContent = result.label;
            button.appendChild(title);

            if (result.subtitle && result.subtitle !== result.label) {
                const subtitle = document.createElement("div");
                subtitle.className = "text-xs text-zinc-500 mt-0.5";
                subtitle.textContent = result.subtitle;
                button.appendChild(subtitle);
            }

            button.addEventListener("click", () => this.selectResult(currentIndex));
            item.appendChild(button);
            this.resultsList.appendChild(item);
        };

        if (presetResults.length > 0) {
            appendHeading("Saved venues", false);
            presetResults.forEach(appendResultButton);
        }

        if (radarResults.length > 0) {
            appendHeading("Places", presetResults.length > 0);
            radarResults.forEach(appendResultButton);
        }

        this.resultsList.classList.toggle("hidden", !openDropdown);
        this.updateSelection();
    },

    selectResult(index) {
        const result = this._results[index];
        if (!result) return;

        pushLocationSelected(this, result);
        this.input.value = result.label;
        this.resultsList.classList.add("hidden");
        this._selectedIndex = -1;
    },

    handleKeydown(event) {
        const buttons = this.getResultButtons();

        if (buttons.length === 0) return;

        switch (event.key) {
            case "ArrowDown":
                event.preventDefault();
                this._selectedIndex = Math.min(this._selectedIndex + 1, buttons.length - 1);
                this.updateSelection();
                break;

            case "ArrowUp":
                event.preventDefault();
                this._selectedIndex = Math.max(this._selectedIndex - 1, 0);
                this.updateSelection();
                break;

            case "Enter":
                if (this._selectedIndex >= 0) {
                    event.preventDefault();
                    this.selectResult(this._selectedIndex);
                }
                break;

            case "Escape":
                this.resultsList.classList.add("hidden");
                this._selectedIndex = -1;
                this.updateSelection();
                break;
        }
    },

    getResultButtons() {
        return Array.from(this.resultsList.querySelectorAll("button[role='option']"));
    },

    updateSelection() {
        const buttons = this.getResultButtons();

        buttons.forEach((button, index) => {
            button.classList.toggle("bg-zinc-50", index === this._selectedIndex);

            if (index === this._selectedIndex) {
                button.scrollIntoView({ block: "nearest" });
            }
        });
    },

    handleClickOutside(event) {
        if (!this.el.contains(event.target)) {
            this.resultsList.classList.add("hidden");
            this._selectedIndex = -1;
            this.updateSelection();
        }
    },
};
