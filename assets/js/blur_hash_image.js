function attachEventListener(imageElement) {
    const alreadyLoaded = imageElement.complete

    // When a reload happens due to LiveView the image might already have loaded
    // and the "onload" event is not firing retroactively. If the image has loaded
    // then do an instant swap of the blur hash to the image.
    if (!alreadyLoaded) {
        imageElement.onload = function() {
            hideBlurHash(imageElement, false)
        }
    } else {
        hideBlurHash(imageElement, true)
    }
}

function hideBlurHash(imageElement, force) {
    const elementId = imageElement.id
    const blurHashCanvas = document.getElementById("blur-hash-" + elementId)

    if (!blurHashCanvas) {
        // If blur hash canvas doesn't exist, just show the image
        imageElement.classList.remove("opacity-0")
        return
    }

    if (force) {
        blurHashCanvas.classList.add("opacity-0")
        imageElement.classList.remove("opacity-0")
    } else {
        // Fade out blur hash and fade in image simultaneously
        blurHashCanvas.classList.add("transition-opacity", "duration-300", "ease-out", "opacity-0")
        imageElement.classList.remove("opacity-0")
        imageElement.classList.add("opacity-100")
    }
}

module.exports = {
    mounted() {
        const element = this.el
        attachEventListener(element)
    },
    updated() {
        const element = this.el
        hideBlurHash(element, true)
    }
}