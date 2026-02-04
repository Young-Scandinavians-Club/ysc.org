export default StickyNavbar = {
    mounted() {
        const navbar = this.el
        const navbarHeight = navbar.offsetHeight
        var sticky = navbar.offsetTop

        function stickyScroll() {
            if (window.scrollY >= sticky) {
                navbar.classList.add("fixed")
                navbar.classList.add("shadow-lg")
                    // Add padding to prevent content jump
                document.body.style.paddingTop = navbarHeight + "px"
            } else {
                navbar.classList.remove("fixed")
                navbar.classList.remove("shadow-lg")
                    // Remove padding when navbar is not fixed
                document.body.style.paddingTop = "0px"
            }
        }

        window.onscroll = function() {
            stickyScroll()
        }
    },

    destroyed() {
        // Clean up padding when component is destroyed
        document.body.style.paddingTop = "0px"
    }
};