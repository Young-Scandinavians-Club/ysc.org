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

function cloneSelected(selected) {
    return { ...selected };
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
                this.refreshTierUI(pendingTier, serverQty);
            }
        }

        this._pendingTier = null;
        this._pendingQty = null;
        this.syncButtonStatesFromDOM();
    },

    syncFromDOM() {
        this.tiers = parseJsonAttr(this.el, "data-tiers", []);
        this.selected = parseJsonAttr(this.el, "data-selected", {});
    },

    onClick(e) {
        const btn = e.target.closest("[data-ticket-action]");
        if (!btn || btn.disabled || !this.el.contains(btn)) return;

        if (this._pendingTier != null) return;

        e.preventDefault();
        e.stopPropagation();

        const action = btn.getAttribute("data-ticket-action");
        const tierId = btn.getAttribute("data-tier-id");
        if (!tierId || !action) return;

        const previousSelected = cloneSelected(this.selected);
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

        const sent = pushEventIfConnected(this, event, { "tier-id": tierId }, (reply) => {
            if (reply && reply.ok === false) {
                this.revertSelection(previousSelected, tierId);
            }
        });

        if (!sent) {
            this.revertSelection(previousSelected, tierId);
        }
    },

    applyOptimisticUI(tierId, qty) {
        this.updateQtyDisplay(tierId, qty);
        this.updateTierCard(tierId, qty > 0);
        this.setButtonsPending(tierId);
    },

    revertSelection(previousSelected, tierId) {
        this.selected = cloneSelected(previousSelected);
        this._pendingTier = null;
        this._pendingQty = null;

        const qty = this.selected[tierId] || 0;
        this.playReject(tierId);
        this.refreshTierUI(tierId, qty);
        this.syncButtonStatesFromDOM();
        this.syncProceedButtonFromDOM();
    },

    refreshTierUI(tierId, qty) {
        this.updateQtyDisplay(tierId, qty);
        this.updateTierCard(tierId, qty > 0);
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

    setButtonsPending(_tierId) {
        for (const btn of this.el.querySelectorAll("[data-ticket-action]")) {
            if (btn.hasAttribute("data-locked-disabled")) continue;

            btn.disabled = true;
        }
    },

    syncButtonStatesFromDOM() {
        for (const btn of this.el.querySelectorAll("[data-ticket-action]")) {
            if (btn.hasAttribute("data-locked-disabled")) {
                btn.disabled = true;
                continue;
            }

            const tierId = btn.getAttribute("data-tier-id");
            const action = btn.getAttribute("data-ticket-action");
            if (!tierId || !action) continue;

            const qty = this.selected[tierId] || 0;

            if (action === "decrease") {
                btn.disabled = qty === 0;
            } else if (action === "increase") {
                btn.disabled = false;
            }
        }
    },

    syncProceedButtonFromDOM() {
        const btn = this.el.querySelector("#ticket-proceed-checkout");
        if (!btn) return;

        const hasSelection = Object.values(this.selected).some((qty) => qty > 0);
        btn.disabled = !hasSelection;
    },
};
