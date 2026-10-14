/**
 * On phones the account settings nav is a horizontally scrolling tab row.
 * Centre the current tab in that row on mount so tabs past the fold
 * (Security, Notifications) never open out of sight. A no-op on desktop,
 * where the list is vertical and does not scroll.
 */
export default {
    mounted() {
        this.centerCurrent();
    },

    centerCurrent() {
        const list = this.el.querySelector(".account-settings-nav-list");
        const current = list && list.querySelector("[aria-current='page']");
        if (!list || !current || list.scrollWidth <= list.clientWidth) return;

        const target =
            current.offsetLeft - (list.clientWidth - current.offsetWidth) / 2;
        list.scrollLeft = Math.max(0, target);
    },
};
