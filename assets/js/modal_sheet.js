// ModalSheet — drag-to-dismiss for modals on phones (< sm), where a modal is a
// full-height sheet that slides up from the bottom.
//
//   * Pull the sheet down and it follows the finger 1:1; the backdrop fades
//     with it.
//   * On release the finger's velocity is projected forward to choose between
//     dismissing and snapping back, then a spring takes over at that velocity.
//   * It only engages when the gesture is downward and the content under the
//     finger is already scrolled to the top, so scrolling a long modal still
//     works. Anything else is left to the browser.
//   * Dismissal runs the modal's own cancel command, so confirm-before-close
//     modals behave as they do for the X button. If the modal is still open
//     afterwards (the server declined to close it), the sheet springs back.
//
// Touch events rather than Pointer Events: we must call preventDefault() on the
// move to stop the page rubber-banding, and pointer events give no such hook.

import {
  VelocityTracker,
  animateSpring,
  prefersReducedMotion,
  project,
} from "./spring";

const PHONE = "(max-width: 639px)"; // Tailwind's `sm` breakpoint
const INTENT_THRESHOLD_PX = 10;
const CLOSE_CHECK_MS = 800; // minimum wait for the server before concluding it declined
const CLOSE_RECHECK_MS = 400; // then re-check while a request is still in flight
const CLOSE_MAX_RECHECKS = 8;

export default {
  mounted() {
    // The hook sits on the modal's root: focus_wrap already owns the panel's
    // hook slot. Touches on the panel bubble up to here.
    this.root = this.el;
    this.panel = document.getElementById(`${this.root.id}-container`);
    if (!this.panel) return;
    this.bg = document.getElementById(`${this.root.id}-bg`);
    this.state = "idle"; // idle | pending | dragging | ignored | settling
    this.y = 0;
    this.anim = null;
    this.tracker = new VelocityTracker();

    this.onTouchStart = this.onTouchStart.bind(this);
    this.onTouchMove = this.onTouchMove.bind(this);
    this.onTouchEnd = this.onTouchEnd.bind(this);
    this.onOpening = () => this.reset();

    this.el.addEventListener("touchstart", this.onTouchStart, { passive: true });
    this.el.addEventListener("touchmove", this.onTouchMove, { passive: false });
    this.el.addEventListener("touchend", this.onTouchEnd);
    this.el.addEventListener("touchcancel", this.onTouchEnd);
    this.el.addEventListener("ysc:modal-opening", this.onOpening);
  },

  destroyed() {
    this.anim?.cancel();
    clearTimeout(this.closeTimer);
    if (!this.panel) return;
    this.el.removeEventListener("touchstart", this.onTouchStart);
    this.el.removeEventListener("touchmove", this.onTouchMove);
    this.el.removeEventListener("touchend", this.onTouchEnd);
    this.el.removeEventListener("touchcancel", this.onTouchEnd);
    this.el.removeEventListener("ysc:modal-opening", this.onOpening);
  },

  // --- helpers -------------------------------------------------------------

  // True when nothing between the touch and the modal can still scroll up.
  atScrollTop(target) {
    for (let node = target; node && node !== this.root; node = node.parentElement) {
      const style = getComputedStyle(node);
      const scrollable = /(auto|scroll)/.test(style.overflowY);
      if (scrollable && node.scrollHeight > node.clientHeight + 1 && node.scrollTop > 0) {
        return false;
      }
    }
    return true;
  },

  isOpen() {
    return this.root.isConnected && getComputedStyle(this.root).display !== "none";
  },

  render(y) {
    this.y = y;
    this.panel.style.translate = `0 ${y}px`;
    if (this.bg) {
      const progress = Math.min(1, y / Math.max(1, Math.min(this.panel.offsetHeight, window.innerHeight)));
      this.bg.style.opacity = String(1 - progress);
    }
  },

  // Hand the panel and backdrop back to their classes.
  reset() {
    this.anim?.cancel();
    this.anim = null;
    clearTimeout(this.closeTimer);
    ["translate", "transition"].forEach((p) => this.panel.style.removeProperty(p));
    this.bg?.style.removeProperty("opacity");
    this.bg?.style.removeProperty("transition");
    this.state = "idle";
    this.y = 0;
  },

  // --- input ---------------------------------------------------------------

  onTouchStart(event) {
    if (!window.matchMedia(PHONE).matches || event.touches.length !== 1) return;

    const touch = event.touches[0];
    this.start = { x: touch.clientX, y: touch.clientY, y0: this.y };
    this.tracker.reset(event.timeStamp, touch.clientY);

    if (this.state === "settling") {
      // Grabbed mid-flight: stop and continue from where it is on screen.
      this.anim?.cancel();
      this.anim = null;
      clearTimeout(this.closeTimer);
      this.state = "dragging";
      return;
    }

    this.state = this.atScrollTop(event.target) ? "pending" : "ignored";
  },

  onTouchMove(event) {
    if (this.state === "idle" || this.state === "ignored") return;
    const touch = event.touches[0];
    const dx = touch.clientX - this.start.x;
    const dy = touch.clientY - this.start.y;

    if (this.state === "pending") {
      if (Math.abs(dx) < INTENT_THRESHOLD_PX && Math.abs(dy) < INTENT_THRESHOLD_PX) return;
      // Only a downward, mostly-vertical pull is ours.
      if (dy <= 0 || Math.abs(dx) > Math.abs(dy)) {
        this.state = "ignored";
        return;
      }
      this.state = "dragging";
      this.start.y += INTENT_THRESHOLD_PX; // the threshold is hysteresis, not travel
      this.panel.style.transition = "none";
      if (this.bg) this.bg.style.transition = "none";
    }

    if (this.state !== "dragging") return;

    event.preventDefault(); // stop the page scrolling or rubber-banding under us
    this.tracker.push(event.timeStamp, touch.clientY);
    this.render(Math.max(0, this.start.y0 + touch.clientY - this.start.y));
  },

  onTouchEnd(event) {
    if (this.state === "pending" || this.state === "ignored") {
      this.state = "idle";
      return;
    }
    if (this.state !== "dragging") return;

    const velocity = this.tracker.velocity(event.timeStamp);
    const height = Math.min(this.panel.offsetHeight, window.innerHeight);
    // Decide from where the gesture is going, not where it stopped.
    const dismiss = this.y + project(velocity) > height * 0.5;

    if (dismiss) this.dismiss(velocity);
    else this.snapBack(velocity);
  },

  // --- release -------------------------------------------------------------

  dismiss(velocity) {
    const target = window.innerHeight; // far enough that the panel is fully off-screen
    const finish = () => {
      this.state = "idle";
      this.exec();
      // If the server kept the modal open (e.g. a confirm-before-close flow),
      // bring the sheet back instead of leaving it stranded off-screen. Closing
      // usually removes this element (and this hook), so only act if it is
      // still here, and not while LiveView says a request is still in flight.
      let rechecks = 0;
      const check = () => {
        if (!this.isOpen()) return this.reset();
        const pending = /phx-[a-z]+-loading/.test(this.root.className);
        if (pending && ++rechecks <= CLOSE_MAX_RECHECKS) {
          this.closeTimer = setTimeout(check, CLOSE_RECHECK_MS);
        } else {
          this.snapBack(0);
        }
      };
      this.closeTimer = setTimeout(check, CLOSE_CHECK_MS);
    };

    if (prefersReducedMotion()) {
      this.render(target);
      finish();
      return;
    }

    this.state = "settling";
    this.anim = animateSpring({
      from: this.y,
      to: target,
      velocity,
      onUpdate: (y) => this.render(y),
      onRest: finish,
    });
  },

  snapBack(velocity) {
    if (prefersReducedMotion()) {
      this.reset();
      return;
    }

    this.state = "settling";
    this.anim = animateSpring({
      from: this.y,
      to: 0,
      velocity,
      onUpdate: (y) => this.render(Math.max(0, y)),
      onRest: () => this.reset(),
    });
  },

  // Run the modal's own cancel command (the same one the X button and Escape use).
  exec() {
    const js = this.root.getAttribute("data-cancel");
    if (js) this.liveSocket.execJS(this.root, js);
  },
};
