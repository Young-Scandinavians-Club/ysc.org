export default {
    mounted() {
        this.button = this.el;
        this.menu = document.getElementById('mobile-toc-menu');
        this.isOpen = false;

        // Toggle menu
        this.button.addEventListener('click', (e) => {
            e.preventDefault();
            this.isOpen = !this.isOpen;
            
            if (this.isOpen) {
                this.menu.classList.remove('hidden');
                this.menu.classList.add('animate-fade-in');
                this.button.querySelector('svg').style.transform = 'rotate(180deg)';
            } else {
                this.menu.classList.add('hidden');
                this.menu.classList.remove('animate-fade-in');
                this.button.querySelector('svg').style.transform = 'rotate(0deg)';
            }
        });

        // Close menu when clicking a link
        const menuLinks = this.menu.querySelectorAll('a');
        menuLinks.forEach(link => {
            link.addEventListener('click', () => {
                this.isOpen = false;
                this.menu.classList.add('hidden');
                this.button.querySelector('svg').style.transform = 'rotate(0deg)';
            });
        });

        // Close menu when clicking outside
        document.addEventListener('click', (e) => {
            if (this.isOpen && !this.button.contains(e.target) && !this.menu.contains(e.target)) {
                this.isOpen = false;
                this.menu.classList.add('hidden');
                this.button.querySelector('svg').style.transform = 'rotate(0deg)';
            }
        });
    }
};
