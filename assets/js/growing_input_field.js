function attachEventListener(element) {
    element.addEventListener('input', resizeInput)
    resizeInput.call(element)
}

function resizeInput() {
    this.style.width = getWidthOfInput(this) + "px"
}

function getWidthOfInput(inputEl) {
    var tmp = document.createElement("span")
    if (inputEl.hasAttribute("growing-input-size") && inputEl.getAttribute("growing-input-size") == "small") {
        tmp.className = "text-sm leading-6 tmp-element"
    } else {
        tmp.className = "font-extrabold leading-6 text-3xl tmp-element"
    }
    tmp.innerHTML = inputEl.value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    document.body.appendChild(tmp)
    var theWidth = tmp.getBoundingClientRect().width
    document.body.removeChild(tmp)
    return theWidth
}

module.exports = {
    mounted() {
        const element = this.el
        attachEventListener(element)
    },

    updated() {
        // Need to resize after LV update to not bug out
        const element = this.el
        resizeInput.call(element)
    }
}