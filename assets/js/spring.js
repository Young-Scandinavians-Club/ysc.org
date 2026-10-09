// Shared physics for gesture-driven hooks (swipe_sheet.js, admin_floating_button.js).
//
// A spring has no duration: it settles on its own from `response` (how quickly,
// in seconds) and `damping` (1.0 = critically damped, no overshoot; < 1.0
// overshoots). New input only changes the target or the starting velocity, so
// motion stays continuous and can be interrupted at any instant.

const DECELERATION_RATE = 0.998;
const VELOCITY_WINDOW_MS = 100;
const STEP_S = 1 / 240; // fixed integration step: stable at any frame rate
const MAX_FRAME_S = 0.064; // don't take a huge step after a stalled frame

export const prefersReducedMotion = () =>
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

// Where a release at `velocity` (px/s) would come to rest, measured from the
// release point. Same exponential-decay model as scroll deceleration.
export function project(velocity, rate = DECELERATION_RATE) {
  return ((velocity / 1000) * rate) / (1 - rate);
}

// Progressive resistance past a boundary: the further over, the less it follows.
export function rubberband(overshoot, dimension, constant = 0.55) {
  return (
    (overshoot * dimension * constant) /
    (dimension + constant * Math.abs(overshoot))
  );
}

// Velocity (units/s) over the last VELOCITY_WINDOW_MS *before release*. A
// pointer that paused before lifting has no velocity, however fast it moved
// earlier.
export class VelocityTracker {
  constructor() {
    this.samples = [];
  }

  reset(t, value) {
    this.samples = [{ t, value }];
  }

  push(t, value) {
    this.samples.push({ t, value });
    while (this.samples.length > 2 && t - this.samples[0].t > VELOCITY_WINDOW_MS) {
      this.samples.shift();
    }
  }

  velocity(now) {
    const recent = this.samples.filter((s) => now - s.t <= VELOCITY_WINDOW_MS);
    if (recent.length < 2) return 0;
    const first = recent[0];
    const last = recent[recent.length - 1];
    const dt = last.t - first.t;
    return dt > 0 ? ((last.value - first.value) / dt) * 1000 : 0;
  }
}

// Animate a single value to `to`, starting at `from` with `velocity` (units/s).
// Returns { cancel() }. 2D motion should use one spring per axis: a single
// spring on the distance desyncs when X and Y have different velocities.
export function animateSpring({
  from,
  to,
  velocity = 0,
  response = 0.35,
  damping = 1,
  onUpdate,
  onRest,
}) {
  const k = Math.pow((2 * Math.PI) / response, 2);
  const c = (4 * Math.PI * damping) / response;
  let x = from;
  let v = velocity;
  let last = performance.now();
  let frame = null;

  const tick = (now) => {
    let elapsed = Math.min((now - last) / 1000, MAX_FRAME_S);
    last = now;
    while (elapsed > 0) {
      const dt = Math.min(STEP_S, elapsed);
      v += (-k * (x - to) - c * v) * dt;
      x += v * dt;
      elapsed -= dt;
    }

    if (Math.abs(x - to) < 0.5 && Math.abs(v) < 5) {
      frame = null;
      onUpdate(to);
      onRest?.();
      return;
    }

    onUpdate(x);
    frame = requestAnimationFrame(tick);
  };

  frame = requestAnimationFrame(tick);

  return {
    cancel() {
      if (frame != null) cancelAnimationFrame(frame);
      frame = null;
    },
  };
}
