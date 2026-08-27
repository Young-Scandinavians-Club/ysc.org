/**
 * DisableOnSubmit Hook
 *
 * For forms that submit with a full-page POST (`action=...`, `phx-update="ignore"`)
 * rather than a LiveView `phx-submit`, so LiveView's own loading machinery never
 * runs. On submit this:
 *   - disables the submit button, so a slow POST can't be triggered twice, and
 *   - adds `phx-submit-loading` to the form and the submit button, which is the
 *     class our `<.button>` component keys its spinner / `phx-disable-with`
 *     label swap off of.
 *
 * Replaces the inline
 * `onsubmit="this.querySelector('[type=submit]')?.setAttribute('disabled','disabled')"`
 * handler, which the Content Security Policy (script-src-attr) blocks.
 *
 * The page navigates away on submit, so nothing needs to undo this — except when
 * the page is restored from the back/forward cache, handled below.
 *
 * Usage:
 *   <form id="login_form" phx-hook="DisableOnSubmit" ...>
 */
const LOADING_CLASS = "phx-submit-loading";

export default {
    mounted() {
        // `<.button>` renders a typeless <button>, so it submits the form by
        // default but does not match `[type=submit]`.
        this.submitButton = (e) =>
            (e && e.submitter) ||
            this.el.querySelector(
                "button[type=submit], input[type=submit], button:not([type])",
            );

        this.onSubmit = (e) => {
            const btn = this.submitButton(e);
            if (btn) {
                btn.setAttribute("disabled", "disabled");
                btn.classList.add(LOADING_CLASS);
            }
            this.el.classList.add(LOADING_CLASS);
        };

        // Restore the button if the browser serves this page from the
        // back/forward cache after a submit.
        this.onPageShow = (e) => {
            if (!e.persisted) return;
            const btn = this.submitButton();
            if (btn) {
                btn.removeAttribute("disabled");
                btn.classList.remove(LOADING_CLASS);
            }
            this.el.classList.remove(LOADING_CLASS);
        };

        this.el.addEventListener("submit", this.onSubmit);
        window.addEventListener("pageshow", this.onPageShow);
    },

    destroyed() {
        this.el.removeEventListener("submit", this.onSubmit);
        window.removeEventListener("pageshow", this.onPageShow);
    },
};
