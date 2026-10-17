// Product tile on the shop listing.
//
// Fades photos in as they load (see `fadeInPendingImages`), and previews a color
// by pointing at its swatch.
//
// LiveView has no hover binding, so a pointer entering a swatch is forwarded to
// that swatch's own click (a client-side `JS` command that swaps the photo; it
// never touches the server). Touch has no hover: a tap is already a click.
// Delegated on the tile so it keeps working when LiveView patches the swatches.
const ShopTile = {
    mounted() {
        this.fadeInPendingImages();

        this.onOver = (e) => {
            if (!window.matchMedia("(hover: hover)").matches) return;

            const swatch = e.target.closest("[data-tile-swatch]");
            if (!swatch || !this.el.contains(swatch)) return;
            // Moving between the swatch's own children is not entering it.
            if (e.relatedTarget && swatch.contains(e.relatedTarget)) return;
            if (swatch.getAttribute("aria-pressed") === "true") return;

            swatch.click();
        };
        this.el.addEventListener("mouseover", this.onOver);
    },

    updated() {
        this.fadeInPendingImages();
    },

    // An image that has not loaded by the time the page goes live is invisible
    // anyway, so hold it at opacity 0 and let CSS fade it in when it arrives.
    // Images that already loaded are left alone (no flash).
    fadeInPendingImages() {
        this.el.querySelectorAll("img.shop-photo-img").forEach((img) => {
            if (img.complete) return;

            const done = () => img.classList.remove("shop-photo-pending");
            img.classList.add("shop-photo-pending");
            img.addEventListener("load", done, { once: true });
            img.addEventListener("error", done, { once: true });
        });
    },

    destroyed() {
        this.el.removeEventListener("mouseover", this.onOver);
    },
};

export default ShopTile;
