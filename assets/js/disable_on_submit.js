/**
 * DisableOnSubmit Hook
 *
 * On form submit, disables the form's submit button so a slow full-page
 * POST can't be triggered twice. Replaces the inline
 * `onsubmit="this.querySelector('[type=submit]')?.setAttribute('disabled','disabled')"`
 * handler, which the Content Security Policy (script-src-attr) blocks.
 *
 * Usage:
 *   <form id="login_form" phx-hook="DisableOnSubmit" ...>
 */
export default {
    mounted() {
        this.onSubmit = () => {
            this.el
                .querySelector("[type=submit]")
                ?.setAttribute("disabled", "disabled");
        };
        this.el.addEventListener("submit", this.onSubmit);
    },

    destroyed() {
        this.el.removeEventListener("submit", this.onSubmit);
    },
};
