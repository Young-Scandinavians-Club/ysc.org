import Sortable from "../vendor/sortable";

function agendaIdFrom(element) {
  return element?.getAttribute("data-agenda_id");
}

module.exports = {
  mounted() {
    const groupName = this.el.dataset.group;

    this.sortable = new Sortable(this.el, {
      animation: 150,
      delay: 100,
      dragClass: "drag-item",
      ghostClass: "drag-ghost",
      handle: ".drag-handle",
      forceFallback: true,
      group: groupName ? { name: groupName, pull: true, put: true } : undefined,
      scroll: true,
      bubbleScroll: true,
      scrollSensitivity: 60,
      scrollSpeed: 12,
      onEnd: (e) => {
        const itemId = e.item.dataset.id;
        if (!itemId) return;

        const params = {
          old: e.oldIndex,
          new: e.newIndex,
          id: itemId,
          agenda_id: e.item.dataset.agendaId || e.item.dataset.agenda_id,
        };

        if (e.to !== e.from) {
          const targetAgendaId = agendaIdFrom(e.to);

          if (targetAgendaId) {
            params.to = { agenda_id: targetAgendaId };
          }
        }

        this.pushEventTo(e.to, "reposition", params);
      },
    });
  },

  destroyed() {
    this.sortable?.destroy();
  },
};
