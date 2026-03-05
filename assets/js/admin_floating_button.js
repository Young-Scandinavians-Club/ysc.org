const STORAGE_KEY = "ysc_admin_button_corner";
const DRAG_THRESHOLD_PX = 5;
const BASE_CLASSES =
  "fixed z-[60] group print:hidden cursor-grab active:cursor-grabbing transition-[left,right,top,bottom] duration-300 ease-out";

const CORNER_CLASSES = {
  "top-left": "top-6 left-6",
  "top-right": "top-6 right-6",
  "bottom-left": "bottom-6 left-6",
  "bottom-right": "bottom-6 right-6",
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
  const vertical =
    clientY < viewportHeight / 2 ? "top" : "bottom";
  const horizontal =
    clientX < viewportWidth / 2 ? "left" : "right";
  return `${vertical}-${horizontal}`;
}

const AdminFloatingButton = {
  mounted() {
    const wrapper = this.el;
    const link = wrapper.querySelector('a[href*="/admin"]');
    if (!link) return;

    applyCorner(wrapper, getStoredCorner());

    this.dragStart = null;
    this.isDragging = false;
    this.justDragged = false;

    this.handleMousedown = this.handleMousedown.bind(this);
    this.handleMousemove = this.handleMousemove.bind(this);
    this.handleMouseup = this.handleMouseup.bind(this);
    this.handleClick = this.handleClick.bind(this);

    wrapper.addEventListener("mousedown", this.handleMousedown);
    document.addEventListener("mousemove", this.handleMousemove);
    document.addEventListener("mouseup", this.handleMouseup);
    link.addEventListener("click", this.handleClick, true);
  },

  destroyed() {
    const wrapper = this.el;
    const link = wrapper?.querySelector('a[href*="/admin"]');
    if (wrapper) {
      wrapper.removeEventListener("mousedown", this.handleMousedown);
    }
    document.removeEventListener("mousemove", this.handleMousemove);
    document.removeEventListener("mouseup", this.handleMouseup);
    if (link) {
      link.removeEventListener("click", this.handleClick, true);
    }
  },

  handleMousedown(event) {
    if (event.button !== 0) return;
    event.preventDefault();
    const wrapper = this.el;
    const rect = wrapper.getBoundingClientRect();
    this.dragStart = {
      x: event.clientX,
      y: event.clientY,
      offsetX: event.clientX - rect.left,
      offsetY: event.clientY - rect.top,
    };
    this.isDragging = false;
  },

  handleMousemove(event) {
    if (this.dragStart == null) return;
    const wrapper = this.el;
    const dx = event.clientX - this.dragStart.x;
    const dy = event.clientY - this.dragStart.y;
    const distance = Math.sqrt(dx * dx + dy * dy);

    if (!this.isDragging && distance >= DRAG_THRESHOLD_PX) {
      this.isDragging = true;
      wrapper.style.transition = "none";
      wrapper.style.right = "auto";
      wrapper.style.bottom = "auto";
      wrapper.style.left = `${event.clientX - this.dragStart.offsetX}px`;
      wrapper.style.top = `${event.clientY - this.dragStart.offsetY}px`;
    }

    if (this.isDragging) {
      wrapper.style.left = `${event.clientX - this.dragStart.offsetX}px`;
      wrapper.style.top = `${event.clientY - this.dragStart.offsetY}px`;
    }
  },

  handleMouseup(event) {
    if (this.dragStart == null) return;

    const wrapper = this.el;

    if (this.isDragging) {
      const viewportWidth = window.innerWidth;
      const viewportHeight = window.innerHeight;
      const corner = cornerFromPoint(
        event.clientX,
        event.clientY,
        viewportWidth,
        viewportHeight
      );
      applyCorner(wrapper, corner);
      saveCorner(corner);
      wrapper.style.left = "";
      wrapper.style.top = "";
      wrapper.style.right = "";
      wrapper.style.bottom = "";
      wrapper.style.transition = "";
      this.justDragged = true;
      const self = this;
      setTimeout(() => {
        self.justDragged = false;
      }, 100);
    }

    this.dragStart = null;
    this.isDragging = false;
  },

  handleClick(event) {
    if (this.justDragged) {
      event.preventDefault();
      event.stopPropagation();
    }
  },
};

export default AdminFloatingButton;
