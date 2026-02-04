import { decode } from "../vendor/blur_hash"

function applyBlurHash(canvasElement) {
    const hash = canvasElement.getAttribute("src")
    // Decode at a fixed size - CSS object-cover will handle scaling
    // Using 100x20 maintains aspect ratio roughly for header (176px height)
    const width = 100
    const height = 20
    const pixels = decode(hash, width, height)
    const ctx = canvasElement.getContext("2d")

    // Set canvas size to decoded size - CSS will scale it
    canvasElement.width = width
    canvasElement.height = height

    const imageData = ctx.createImageData(width, height)
    imageData.data.set(pixels)
    ctx.putImageData(imageData, 0, 0)
}

module.exports = {
    mounted() {
        const element = this.el
        applyBlurHash(element)
    },
    updated() {
        const element = this.el
        applyBlurHash(element)
    }
}