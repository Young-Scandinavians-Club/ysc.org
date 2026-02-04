export default {
    mounted() {
        this.handleScroll = () => {
            const heroSection = document.querySelector("#history-hero");
            const backToTopButton = this.el;

            if (heroSection && backToTopButton) {
                const heroBottom = heroSection.getBoundingClientRect().bottom;
                if (heroBottom < 0) {
                    backToTopButton.classList.remove("opacity-0", "pointer-events-none");
                    backToTopButton.classList.add("opacity-100");
                } else {
                    backToTopButton.classList.add("opacity-0", "pointer-events-none");
                    backToTopButton.classList.remove("opacity-100");
                }
            }
        };

        this.handleClick = (e) => {
            e.preventDefault();
            window.scrollTo({ top: 0, behavior: "smooth" });
        };

        this.el.addEventListener("click", this.handleClick);
        window.addEventListener("scroll", this.handleScroll);
        this.handleScroll(); // Check initial state
    },

    destroyed() {
        if (this.handleScroll) {
            window.removeEventListener("scroll", this.handleScroll);
        }
        if (this.handleClick) {
            this.el.removeEventListener("click", this.handleClick);
        }
    }
};