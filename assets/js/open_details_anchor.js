// Anchor links that target content inside a collapsed <details> (e.g. the
// financials archive) can't scroll to it. Open the details first, then let the
// browser's default anchor scroll proceed.
function openDetailsForHash() {
    const id = decodeURIComponent(window.location.hash.slice(1));
    const target = id && document.getElementById(id);
    const details = target && target.closest("details");

    if (details && !details.open) {
        details.open = true;
        target.scrollIntoView();
    }
}

document.addEventListener("click", (event) => {
    const link = event.target.closest("a[data-opens-details]");
    if (!link) return;

    const details = document.getElementById(link.dataset.opensDetails);
    if (details) details.open = true;
});

window.addEventListener("hashchange", openDetailsForHash);
document.addEventListener("DOMContentLoaded", openDetailsForHash);
