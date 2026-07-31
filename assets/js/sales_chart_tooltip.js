const TOOLTIP_MARGIN = 8;

const SalesChartTooltip = {
    mounted() {
        this.tooltip = document.getElementById(this.el.dataset.tooltipTarget);

        this.handleMouseOver = (e) => {
            const bar = e.target.closest("[data-tooltip]");
            if (!bar || !this.tooltip) return;

            this.tooltip.textContent = bar.dataset.tooltip;
            this.tooltip.style.display = "block";
            this.position(bar);
        };

        this.handleMouseMove = (e) => {
            if (!this.tooltip || this.tooltip.style.display !== "block") return;
            const bar = e.target.closest("[data-tooltip]");
            if (bar) this.position(bar);
        };

        this.handleMouseOut = (e) => {
            const bar = e.target.closest("[data-tooltip]");
            if (!bar) return;
            if (bar.contains(e.relatedTarget)) return;
            if (this.tooltip) this.tooltip.style.display = "none";
        };

        this.el.addEventListener("mouseover", this.handleMouseOver);
        this.el.addEventListener("mousemove", this.handleMouseMove);
        this.el.addEventListener("mouseout", this.handleMouseOut);
    },

    position(bar) {
        const barRect = bar.getBoundingClientRect();
        const tipRect = this.tooltip.getBoundingClientRect();

        let left = barRect.left + barRect.width / 2 - tipRect.width / 2;
        left = Math.max(TOOLTIP_MARGIN, Math.min(left, window.innerWidth - tipRect.width - TOOLTIP_MARGIN));

        let top = barRect.top - tipRect.height - TOOLTIP_MARGIN;
        if (top < TOOLTIP_MARGIN) top = barRect.bottom + TOOLTIP_MARGIN;

        this.tooltip.style.left = `${left}px`;
        this.tooltip.style.top = `${top}px`;
    },

    destroyed() {
        if (this.handleMouseOver) this.el.removeEventListener("mouseover", this.handleMouseOver);
        if (this.handleMouseMove) this.el.removeEventListener("mousemove", this.handleMouseMove);
        if (this.handleMouseOut) this.el.removeEventListener("mouseout", this.handleMouseOut);
        if (this.tooltip) this.tooltip.style.display = "none";
    }
};

export default SalesChartTooltip;
