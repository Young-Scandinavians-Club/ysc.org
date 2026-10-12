// AdminFloatingButton — a draggable shortcut that snaps to the nearest corner.
//
//   * Pointer Events (mouse, touch and pen through one path) with pointer
//     capture, so the drag keeps tracking outside the button.
//   * The button moves with `translate`, 1:1 with the pointer; no layout
//     properties are touched while dragging.
//   * On release the corner is chosen from where the gesture is *going* (the
//     release velocity projected forward), then the button springs there. The
//     spring is independent on X and Y and inherits the release velocity, so
//     there is no seam between the drag and the animation.
//   * It can be grabbed again mid-flight and continues from where it is on
//     screen.

import {
  VelocityTracker,
  animateSpring,
  prefersReducedMotion,
  project,
} from "./spring";

const STORAGE_KEY = "ysc_admin_button_corner";
const DRAG_THRESHOLD_PX = 5;
const MAX_RELEASE_VELOCITY = 2500; // px/s; a hard throw must not fling it off-screen
const VIEWPORT_MARGIN_PX = 4; // the spring may overshoot its corner, but never leave the screen
const BASE_CLASSES =
  "fixed z-110 group print:hidden cursor-grab active:cursor-grabbing touch-none select-none";

const CORNER_CLASSES = {
  "top-left": "admin-floating-top-left",
  "top-right": "admin-floating-top-right",
  "bottom-left": "admin-floating-bottom-left",
  "bottom-right": "admin-floating-bottom-right",
};

const VALID_CORNERS = Object.keys(CORNER_CLASSES);

function getStoredCorner() {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (VALID_CORNERS.includes(stored)) return stored;
  } catch (_) {}
  return "bottom-left";
}

function saveCorner(corner) {
  try {
    localStorage.setItem(STORAGE_KEY, corner);
  } catch (_) {}
}

function applyCorner(el, corner) {
  const rightCorner = corner === "top-right" || corner === "bottom-right";
  const cornerRightClass = rightCorner ? " corner-right" : "";
  el.className = `${BASE_CLASSES} ${CORNER_CLASSES[corner]}${cornerRightClass}`;
}

function cornerFromPoint(clientX, clientY, viewportWidth, viewportHeight) {
  const vertical = clientY < viewportHeight / 2 ? "top" : "bottom";
  const horizontal = clientX < viewportWidth / 2 ? "left" : "right";
  return `${vertical}-${horizontal}`;
}

const AdminFloatingButton = {
  mounted() {
    const wrapper = this.el;
    this.link = wrapper.querySelector('a[href*="/admin"]');
    if (!this.link) return;

    applyCorner(wrapper, getStoredCorner());

    this.tx = 0; // translate from the corner's resting position
    this.ty = 0;
    this.pointerId = null;
    this.dragging = false;
    this.justDragged = false;
    this.springs = [];
    this.vx = new VelocityTracker();
    this.vy = new VelocityTracker();

    this.onPointerDown = this.onPointerDown.bind(this);
    this.onPointerMove = this.onPointerMove.bind(this);
    this.onPointerUp = this.onPointerUp.bind(this);
    this.onClick = this.onClick.bind(this);
    this.onDragStart = (event) => event.preventDefault(); // no native link drag

    wrapper.addEventListener("pointerdown", this.onPointerDown);
    wrapper.addEventListener("pointermove", this.onPointerMove);
    wrapper.addEventListener("pointerup", this.onPointerUp);
    wrapper.addEventListener("pointercancel", this.onPointerUp);
    wrapper.addEventListener("dragstart", this.onDragStart);
    // Capture phase: swallow the click that follows a drag before it navigates.
    this.link.addEventListener("click", this.onClick, true);
  },

  destroyed() {
    this.cancelSprings();
    const wrapper = this.el;
    wrapper.removeEventListener("pointerdown", this.onPointerDown);
    wrapper.removeEventListener("pointermove", this.onPointerMove);
    wrapper.removeEventListener("pointerup", this.onPointerUp);
    wrapper.removeEventListener("pointercancel", this.onPointerUp);
    wrapper.removeEventListener("dragstart", this.onDragStart);
    this.link?.removeEventListener("click", this.onClick, true);
  },

  render() {
    this.el.style.translate = `${this.tx}px ${this.ty}px`;
  },

  cancelSprings() {
    this.springs.forEach((spring) => spring.cancel());
    this.springs = [];
  },

  onPointerDown(event) {
    if (!event.isPrimary || (event.pointerType === "mouse" && event.button !== 0)) return;

    // Grabbed mid-flight: stop the springs; tx/ty already hold the live offset.
    this.cancelSprings();
    this.pointerId = event.pointerId;
    this.dragging = false;
    this.start = { x: event.clientX, y: event.clientY, tx: this.tx, ty: this.ty };
    this.vx.reset(event.timeStamp, event.clientX);
    this.vy.reset(event.timeStamp, event.clientY);
  },

  onPointerMove(event) {
    if (event.pointerId !== this.pointerId) return;

    const dx = event.clientX - this.start.x;
    const dy = event.clientY - this.start.y;

    if (!this.dragging) {
      if (Math.hypot(dx, dy) < DRAG_THRESHOLD_PX) return;
      this.dragging = true;
      this.justDragged = true;
      try {
        this.el.setPointerCapture(event.pointerId);
      } catch (_) {
        // The pointer is already gone; bubbling still delivers the moves.
      }
    }

    this.vx.push(event.timeStamp, event.clientX);
    this.vy.push(event.timeStamp, event.clientY);
    this.tx = this.start.tx + dx;
    this.ty = this.start.ty + dy;
    this.render();
  },

  onPointerUp(event) {
    if (event.pointerId !== this.pointerId) return;
    this.pointerId = null;

    if (this.dragging) {
      this.dragging = false;
      this.release(event);
      // The click (if any) fires synchronously after pointerup.
      setTimeout(() => (this.justDragged = false), 100);
    } else if (this.tx !== 0 || this.ty !== 0) {
      // Grabbed mid-flight and let go without dragging: carry on to rest.
      this.settle(0, 0);
    }
  },

  onClick(event) {
    if (this.justDragged) {
      event.preventDefault();
      event.stopPropagation();
    }
  },

  release(event) {
    const clamp = (v) => Math.max(-MAX_RELEASE_VELOCITY, Math.min(MAX_RELEASE_VELOCITY, v));
    const vx = clamp(this.vx.velocity(event.timeStamp));
    const vy = clamp(this.vy.velocity(event.timeStamp));

    // Choose the corner from where the gesture is going, not where it stopped.
    const corner = cornerFromPoint(
      event.clientX + project(vx),
      event.clientY + project(vy),
      window.innerWidth,
      window.innerHeight,
    );

    // FLIP: remember where the button is on screen, move it to its new corner,
    // then express the old position as an offset from the new rest position.
    const before = this.el.getBoundingClientRect();
    this.el.style.translate = "";
    applyCorner(this.el, corner);
    saveCorner(corner);
    const after = this.el.getBoundingClientRect();

    this.tx = before.left - after.left;
    this.ty = before.top - after.top;
    this.render();

    // Where the offset may travel while settling. The release position itself
    // is always allowed, so a button dropped half off-screen doesn't jump.
    this.bounds = {
      minX: Math.min(VIEWPORT_MARGIN_PX - after.left, this.tx),
      maxX: Math.max(window.innerWidth - VIEWPORT_MARGIN_PX - after.right, this.tx),
      minY: Math.min(VIEWPORT_MARGIN_PX - after.top, this.ty),
      maxY: Math.max(window.innerHeight - VIEWPORT_MARGIN_PX - after.bottom, this.ty),
    };
    this.settle(vx, vy);
  },

  // Spring the offset back to zero. X and Y are independent springs: a single
  // spring on the distance would desync when the axes have different velocities.
  settle(vx, vy) {
    if (prefersReducedMotion()) {
      this.tx = 0;
      this.ty = 0;
      this.render();
      return;
    }

    this.cancelSprings();
    this.springs = [
      animateSpring({
        from: this.tx,
        to: 0,
        velocity: vx,
        onUpdate: (x) => {
          this.tx = this.bounds ? Math.max(this.bounds.minX, Math.min(this.bounds.maxX, x)) : x;
          this.render();
        },
      }),
      animateSpring({
        from: this.ty,
        to: 0,
        velocity: vy,
        onUpdate: (y) => {
          this.ty = this.bounds ? Math.max(this.bounds.minY, Math.min(this.bounds.maxY, y)) : y;
          this.render();
        },
      }),
    ];
  },
};

export default AdminFloatingButton;
