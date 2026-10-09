// Modal origin: a dialog should grow out of whatever opened it and return there
// when it closes, so the spatial relationship between control and content is
// obvious. show_modal/1 dispatches `ysc:modal-opening` on the panel just before
// it appears; this sets the panel's transform-origin from the last interaction.
//
// Panels are centred in the viewport, so the origin can be expressed relative
// to the panel's own centre (`calc(50% + Npx)`) without measuring it, which
// matters because the panel is still display:none when the event fires.

const FRESH_MS = 1500; // an older interaction is not what opened the modal
const MAX_OFFSET = 0.45; // as a fraction of the viewport; keeps the origin sane

let last = null;

// A LiveView patch re-renders the panel and drops inline styles, so the origin
// is remembered per modal and re-applied when it closes.
const origins = new Map();

document.addEventListener(
  "pointerdown",
  (event) => {
    last = { x: event.clientX, y: event.clientY, t: performance.now() };
  },
  true,
);

// Keyboard activation (Enter/Space on a focused control) has no pointer position.
document.addEventListener(
  "keydown",
  (event) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    const rect = event.target?.getBoundingClientRect?.();
    if (!rect || (rect.width === 0 && rect.height === 0)) return;
    last = {
      x: rect.left + rect.width / 2,
      y: rect.top + rect.height / 2,
      t: performance.now(),
    };
  },
  true,
);

window.addEventListener("ysc:modal-opening", (event) => {
  const panel = event.target;
  if (!(panel instanceof HTMLElement)) return;

  if (!last || performance.now() - last.t > FRESH_MS) {
    // Opened by the server with no recent interaction: grow from the centre.
    origins.delete(panel.id);
    panel.style.removeProperty("transform-origin");
    return;
  }

  const clamp = (value, limit) => Math.max(-limit, Math.min(limit, value));
  const dx = clamp(last.x - window.innerWidth / 2, window.innerWidth * MAX_OFFSET);
  const dy = clamp(last.y - window.innerHeight / 2, window.innerHeight * MAX_OFFSET);
  const origin = `calc(50% + ${dx}px) calc(50% + ${dy}px)`;
  origins.set(panel.id, origin);
  panel.style.transformOrigin = origin;
});

// Close toward where it came from.
window.addEventListener("ysc:modal-closing", (event) => {
  const panel = event.target;
  const origin = panel instanceof HTMLElement && origins.get(panel.id);
  if (origin) panel.style.transformOrigin = origin;
});
