import { pushEventIfConnected } from "./live_view_safe_push";

function parseJsonAttr(el, name, fallback) {
    try {
        const raw = el.getAttribute(name);
        if (!raw) return fallback;
        return JSON.parse(raw);
    } catch (_) {
        return fallback;
    }
}

function formatCents(cents) {
    return new Intl.NumberFormat(undefined, { style: "currency", currency: "USD" }).format(
        cents / 100
    );
}

export default {
    mounted() {
        this._pendingTier = null;
        this._pendingQty = null;
        this._clickHandler = (e) => this.onClick(e);
        this.el.addEventListener("click", this._clickHandler);
        this.syncFromDOM();
    },

    destroyed() {
        this.el.removeEventListener("click", this._clickHandler);
    },

    updated() {
        const pendingTier = this._pendingTier;
        const pendingQty = this._pendingQty;

        this.syncFromDOM();

        if (pendingTier != null) {
            const serverQty = this.selected[pendingTier] || 0;
            if (serverQty !== pendingQty) {
                this.playReject(pendingTier);
            }
        }

        this._pendingTier = null;
        this._pendingQty = null;
    },

    syncFromDOM() {
        this.tiers = parseJsonAttr(this.el, "data-tiers", []);
        this.selected = parseJsonAttr(this.el, "data-selected", {});
    },

    onClick(e) {
        const btn = e.target.closest("[data-ticket-action]");
        if (!btn || btn.disabled || !this.el.contains(btn)) return;

        e.preventDefault();
        e.stopPropagation();

        const action = btn.getAttribute("data-ticket-action");
        const tierId = btn.getAttribute("data-tier-id");
        if (!tierId || !action) return;

        const current = this.selected[tierId] || 0;
        const delta = action === "increase" ? 1 : -1;
        const next = Math.max(0, current + delta);

        if (next === current) return;

        if (next === 0) {
            delete this.selected[tierId];
        } else {
            this.selected[tierId] = next;
        }

        this._pendingTier = tierId;
        this._pendingQty = next;

        this.applyOptimisticUI(tierId, next);

        const event =
            action === "increase" ? "increase-ticket-quantity" : "decrease-ticket-quantity";
        pushEventIfConnected(this, event, { "tier-id": tierId });
    },

    applyOptimisticUI(tierId, qty) {
        this.updateQtyDisplay(tierId, qty);
        this.updateTierCard(tierId, qty > 0);
        this.updateButtons(tierId, qty);
        this.updateOrderSummary();
        this.updateProceedButton();
    },

    updateQtyDisplay(tierId, qty) {
        const el = this.el.querySelector(`#ticket-qty-${tierId}`);
        if (!el) return;

        el.textContent = String(qty);
        el.classList.remove("ticket-qty-pop");
        void el.offsetWidth;
        el.classList.add("ticket-qty-pop");
    },

    playReject(tierId) {
        const el = this.el.querySelector(`#ticket-qty-${tierId}`);
        if (!el) return;

        el.classList.remove("ticket-qty-reject");
        void el.offsetWidth;
        el.classList.add("ticket-qty-reject");
    },

    updateTierCard(tierId, selected) {
        const card = this.el.querySelector(`[data-tier-card][data-tier-id="${tierId}"]`);
        if (!card) return;

        if (card.classList.contains("opacity-60") || card.classList.contains("opacity-70")) {
            return;
        }

        card.classList.remove("border-zinc-200", "bg-white", "border-blue-500", "bg-blue-50");

        if (selected) {
            card.classList.add("border-blue-500", "bg-blue-50");
        } else {
            card.classList.add("border-zinc-200", "bg-white");
        }
    },

    updateButtons(tierId, qty) {
        const decreaseBtn = this.el.querySelector(
            `[data-ticket-action="decrease"][data-tier-id="${tierId}"]`
        );

        if (!decreaseBtn || decreaseBtn.hasAttribute("data-locked-disabled")) return;

        decreaseBtn.disabled = qty === 0;
    },

    updateOrderSummary() {
        const linesEl = this.el.querySelector("[data-ticket-order-lines]");
        const emptyEl = this.el.querySelector("[data-ticket-order-empty]");
        const totalEl = this.el.querySelector("[data-ticket-order-total]");
        const discountSection = this.el.querySelector("[data-ticket-order-discounts]");

        const entries = Object.entries(this.selected).filter(([, qty]) => qty > 0);
        const hasRegularTickets = entries.some(([tierId]) =>
            this.tiers.some((tier) => tier.id === tierId)
        );

        if (!hasRegularTickets) {
            if (emptyEl) emptyEl.classList.remove("hidden");
            if (linesEl) linesEl.classList.add("hidden");
            if (discountSection) discountSection.classList.add("hidden");
            if (totalEl) totalEl.textContent = formatCents(0);
            return;
        }

        if (emptyEl) emptyEl.classList.add("hidden");
        if (linesEl) linesEl.classList.remove("hidden");

        let totalCents = 0;
        let html = "";

        for (const [tierId, qty] of entries) {
            const tier = this.tiers.find((t) => t.id === tierId);
            if (!tier) continue;

            const lineCents = tier.price_cents * qty;
            totalCents += lineCents;
            const qtyLabel = qty > 1 ? ` × ${qty}` : "";

            html += `<div class="space-y-1"><div class="flex justify-between text-base"><span>${tier.name}${qtyLabel}</span><span class="font-medium">${formatCents(lineCents)}</span></div></div>`;
        }

        if (linesEl) linesEl.innerHTML = html;
        if (discountSection) discountSection.classList.add("hidden");
        if (totalEl) totalEl.textContent = formatCents(totalCents);
    },

    updateProceedButton() {
        const btn = this.el.querySelector("#ticket-proceed-checkout");
        if (!btn) return;

        const hasSelection = Object.values(this.selected).some((qty) => qty > 0);
        btn.disabled = !hasSelection;
    },
};
