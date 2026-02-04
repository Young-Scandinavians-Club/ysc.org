let Uploaders = {}

Uploaders.S3 = function(entries, onViewError) {
    entries.forEach(entry => {
        let formData = new FormData()
        let { url, fields } = entry.meta
        Object.entries(fields).forEach(([key, val]) => formData.append(key, val))
        formData.append("file", entry.file)
        let xhr = new XMLHttpRequest()
        onViewError(() => xhr.abort())

        xhr.onload = () => {
            // S3 returns 204 No Content on success, but Tigris returns 200 OK
            // Accept both as success for compatibility
            if (xhr.status === 204 || xhr.status === 200) {
                entry.progress(100)
            } else {
                // Log error details for debugging
                console.error("S3 upload failed:", {
                    status: xhr.status,
                    statusText: xhr.statusText,
                    response: xhr.responseText,
                    url: url
                })
                entry.error()
            }
        }

        xhr.onerror = () => {
            // Log network/CORS errors for debugging
            console.error("S3 upload network error:", {
                url: url,
                readyState: xhr.readyState,
                status: xhr.status
            })
            entry.error()
        }

        xhr.upload.addEventListener("progress", (event) => {
            if (event.lengthComputable) {
                let percent = Math.round((event.loaded / event.total) * 100)
                if (percent < 100) { entry.progress(percent) }
            }
        })

        xhr.open("POST", url, true)
        xhr.send(formData)
    })
}

export default Uploaders;