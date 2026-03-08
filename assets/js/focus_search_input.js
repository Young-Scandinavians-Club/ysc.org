/**
 * FocusSearchInput Hook
 *
 * When the user clicks the clear (X) button, the server sets data-focus-input
 * on the form. This hook's updated() runs after the DOM is patched and
 * focuses the target input so the user can immediately type a new search.
 */
const FocusSearchInput = {
    updated() {
        const targetId = this.el.getAttribute("data-focus-input");
        if (targetId && targetId.trim() !== "") {
            const input = this.el.querySelector(`#${CSS.escape(targetId)}`);
            if (input) {
                input.focus();
            }
        }
    }
};

export default FocusSearchInput;
