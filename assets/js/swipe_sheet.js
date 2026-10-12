// SwipeSheet — drag-to-dismiss for the slide-in mobile menu (hamburger_menu/1).
//
// Open/close from buttons stays a LiveView.JS class toggle (data-open /
// data-close hold those commands). This hook adds the physical layer:
//
//   * The panel tracks the finger 1:1 and keeps the offset from where it was
//     grabbed, with rubber-banding when dragged past the open edge.
//   * The scrim fades with the panel's progress, so it is part of the gesture.
//   * On release the finger's velocity is projected forward (the same
//     exponential-decay model as scroll deceleration) to choose between open
//     and closed, then handed to a spring so there is no seam between drag
//     and animation.
//   * The panel can be grabbed while it is still moving (including mid CSS
//     transition from a button press) and continues from its on-screen
//     position, not its target.
//
// Dragging uses touch/pen pointers only; a mouse never drags the menu.

import {
  VelocityTracker,
  animateSpring,
  prefersReducedMotion,
  project,
  rubberband,
} from "./spring";

const INTENT_THRESHOLD_PX = 10; // hysteresis before committing to a direction
const SPRING_RESPONSE_S = 0.35; // how quickly the spring settles; not a duration
const SPRING_DAMPING = 1.0; // critically damped: no overshoot

export default {
  mounted() {
    this.panel = this.el;
    this.overlay = document.getElementById(`${this.el.id}-overlay`);
    this.state = "idle"; // idle | pending | dragging | settling
    this.x = this.restX(this.isOpen());
    this.frame = null;
    this.anim = null;
    this.velocityTracker = new VelocityTracker();

    this.onPointerDown = this.onPointerDown.bind(this);
    this.onPointerMove = this.onPointerMove.bind(this);
    this.onPointerUp = this.onPointerUp.bind(this);
    this.onKeyDown = this.onKeyDown.bind(this);
    this.onOverlayClick = this.onOverlayClick.bind(this);

    this.targets = [this.panel, this.overlay].filter(Boolean);
    this.targets.forEach((el) => {
      el.addEventListener("pointerdown", this.onPointerDown);
      el.addEventListener("pointermove", this.onPointerMove);
      el.addEventListener("pointerup", this.onPointerUp);
      el.addEventListener("pointercancel", this.onPointerUp);
    });
    // Capture phase so a drag that ends on the scrim does not also "tap" it closed.
    this.overlay?.addEventListener("click", this.onOverlayClick, true);
    document.addEventListener("keydown", this.onKeyDown);
  },

  destroyed() {
    this.cancelFrame();
    this.targets.forEach((el) => {
      el.removeEventListener("pointerdown", this.onPointerDown);
      el.removeEventListener("pointermove", this.onPointerMove);
      el.removeEventListener("pointerup", this.onPointerUp);
      el.removeEventListener("pointercancel", this.onPointerUp);
    });
    this.overlay?.removeEventListener("click", this.onOverlayClick, true);
    document.removeEventListener("keydown", this.onKeyDown);
  },

  // --- state helpers -------------------------------------------------------

  isOpen() {
    return !this.panel.classList.contains("-translate-x-full");
  },

  width() {
    return this.panel.offsetWidth;
  },

  // Translate-x of the panel at rest: 0 when open, -width when closed.
  restX(open) {
    return open ? 0 : -this.width();
  },

  // The panel's live on-screen offset (the "presentation" value). Reading the
  // rect, not the logical open/closed state, is what makes interruption seamless
  // even while a CSS transition is running.
  presentationX() {
    return this.panel.getBoundingClientRect().left;
  },

  cancelFrame() {
    this.anim?.cancel();
    this.anim = null;
    if (this.frame != null) {
      cancelAnimationFrame(this.frame);
      this.frame = null;
    }
  },

  // --- rendering -----------------------------------------------------------

  render(x) {
    this.x = x;
    const width = this.width();
    // The individual `translate` property, not `transform`: Tailwind's
    // -translate-x-full sets `translate`, and the two would otherwise add up.
    this.panel.style.translate = `${x}px 0`;
    if (this.overlay) {
      const progress = Math.min(1, Math.max(0, 1 + x / width));
      this.overlay.style.opacity = String(progress);
    }
  },

  // Take over from the CSS classes: freeze at the current on-screen position.
  takeControl() {
    this.panel.style.transition = "none";
    if (this.overlay) {
      this.overlay.style.transition = "none";
      this.overlay.style.visibility = "visible";
      this.overlay.style.pointerEvents = "auto";
    }
    this.render(this.presentationX());
  },

  // Hand back to the CSS classes once the inline styles describe the same state.
  releaseControl() {
    ["translate", "transition"].forEach((p) => this.panel.style.removeProperty(p));
    if (this.overlay) {
      ["opacity", "transition", "visibility", "pointer-events"].forEach((p) =>
        this.overlay.style.removeProperty(p),
      );
    }
  },

  // --- input ---------------------------------------------------------------

  onPointerDown(event) {
    if (event.pointerType === "mouse" || !event.isPrimary) return;
    if (!this.isOpen() && this.state !== "settling") return;

    this.pointerId = event.pointerId;
    this.start = { x: event.clientX, y: event.clientY };
    this.velocityTracker.reset(event.timeStamp, event.clientX);

    if (this.state === "settling") {
      // Grabbed mid-flight: stop the spring and continue from where it is.
      this.cancelFrame();
      this.state = "pending";
      this.grabOffset = event.clientX - this.x;
      return;
    }

    // Mid CSS transition (from a button press)? Freeze it where it is.
    const x = this.presentationX();
    this.grabOffset = event.clientX - x;
    this.state = "pending";
    if (Math.abs(x) > 0.5 && Math.abs(x + this.width()) > 0.5) this.takeControl();
  },

  onPointerMove(event) {
    if (event.pointerId !== this.pointerId) return;

    if (this.state === "pending") {
      const dx = event.clientX - this.start.x;
      const dy = event.clientY - this.start.y;
      if (Math.abs(dx) < INTENT_THRESHOLD_PX && Math.abs(dy) < INTENT_THRESHOLD_PX) return;

      if (Math.abs(dy) > Math.abs(dx)) {
        // Vertical intent: let the menu scroll. Nothing to undo unless we froze it.
        this.abandon();
        return;
      }

      this.state = "dragging";
      this.justDragged = true;
      this.takeControl();
      this.grabOffset = event.clientX - this.x; // keep the offset from where it was grabbed
      try {
        event.currentTarget.setPointerCapture(event.pointerId);
      } catch (_) {
        // The pointer is already gone (e.g. lifted between events); the move
        // handlers below still work through normal event bubbling.
      }
    }

    if (this.state !== "dragging") return;

    this.velocityTracker.push(event.timeStamp, event.clientX);

    const raw = event.clientX - this.grabOffset;
    const x = raw > 0 ? rubberband(raw, this.width()) : Math.max(raw, -this.width());
    this.render(x);
  },

  onPointerUp(event) {
    if (event.pointerId !== this.pointerId) return;
    this.pointerId = null;

    if (this.state === "dragging") {
      this.release(this.velocityTracker.velocity(event.timeStamp));
    } else if (this.state === "pending") {
      // A tap, or a freeze-then-let-go: finish whatever was in flight.
      if (this.panel.style.translate) this.release(0);
      else this.state = "idle";
    }
  },

  // A vertical scroll started: give control back untouched.
  abandon() {
    const frozen = Boolean(this.panel.style.translate);
    this.pointerId = null;
    if (frozen) this.release(0);
    else this.state = "idle";
  },

  // --- release -------------------------------------------------------------

  release(velocity) {
    const width = this.width();
    // Choose from where the gesture is *going*, not where it stopped.
    const projected = this.x + project(velocity);
    const open = Math.abs(projected) < Math.abs(projected + width);
    const target = this.restX(open);

    if (prefersReducedMotion()) {
      this.render(target);
      this.finish(open);
      return;
    }

    this.state = "settling";
    this.anim = animateSpring({
      from: this.x,
      to: target,
      velocity,
      response: SPRING_RESPONSE_S,
      damping: SPRING_DAMPING,
      onUpdate: (x) => this.render(x),
      onRest: () => this.finish(open),
    });
  },

  // Sync the class-based state (and aria/inert/scroll lock, via the same JS
  // commands the buttons use) with where the gesture ended, then drop the
  // inline styles. Both describe the same position, so nothing visibly moves.
  finish(open) {
    const complete = () => {
      this.releaseControl();
      this.state = "idle";
      this.x = this.restX(open);
      // Swallow the click the browser may still synthesize after a drag.
      setTimeout(() => (this.justDragged = false), 50);
    };

    if (open === this.isOpen()) return complete();

    this.exec(open ? "open" : "close");
    // LiveView applies JS class changes on a later frame. Keep the inline
    // position until they have landed; releasing earlier would snap the panel
    // back to the old class state for a frame.
    let frames = 0;
    const wait = () => {
      if (open === this.isOpen() || ++frames > 10) return complete();
      this.frame = requestAnimationFrame(wait);
    };
    this.frame = requestAnimationFrame(wait);
  },

  exec(kind) {
    const js = this.panel.dataset[kind];
    if (js) this.liveSocket.execJS(this.panel, js);
  },

  onOverlayClick(event) {
    if (this.justDragged) {
      event.stopImmediatePropagation();
      event.preventDefault();
    }
  },

  onKeyDown(event) {
    if (event.key === "Escape" && this.isOpen() && this.state === "idle") {
      this.exec("close");
      document.querySelector(`[aria-controls="${this.panel.id}"]`)?.focus();
    }
  },
};
