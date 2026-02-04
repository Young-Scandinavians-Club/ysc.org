/**
 * ClipboardCopy Hook
 *
 * Provides copy-to-clipboard functionality with visual feedback
 *
 * Usage:
 *   <button phx-hook="ClipboardCopy" data-copy="text to copy">
 *     <.icon name="hero-clipboard" />
 *   </button>
 */
export default {
    mounted() {
        this.el.addEventListener('click', (e) => {
            e.preventDefault();
            const textToCopy = this.el.getAttribute('data-copy');

            if (textToCopy) {
                navigator.clipboard.writeText(textToCopy).then(() => {
                    // Find the clipboard icon
                    const icon = this.el.querySelector('[class*="hero-clipboard"]');

                    if (icon) {
                        // Store original classes
                        const originalClasses = icon.className;

                        // Replace with checkmark
                        icon.className = icon.className.replace('hero-clipboard', 'hero-check');
                        icon.classList.add('text-green-600');

                        // Restore original icon after 1.5 seconds
                        setTimeout(() => {
                            icon.className = originalClasses;
                        }, 1500);
                    }
                }).catch((err) => {
                    console.error('Failed to copy to clipboard:', err);
                });
            }
        });
    }
};
