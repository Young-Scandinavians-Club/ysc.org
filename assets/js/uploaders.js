// Presigned S3 POST target: `url` and `fields` always come from the LiveView
// presign callback (Elixir: `S3Config.upload_url/0` or `avatars_upload_url/0`).
//
// When the HTML root has `data-s3-use-custom-domain="true"` (see root.html.heex /
// admin_root.html.heex + `S3_USE_CUSTOM_DOMAIN`), we refuse Tigris virtual-host
// POST targets so CORS misconfigurations fail fast in the client with a clear log line.

let Uploaders = {}

function s3UseCustomDomainFromPage() {
    return document.documentElement.getAttribute("data-s3-use-custom-domain") === "true"
}

function isTigrisFlyStorageUploadHost(hostname) {
    return hostname === "fly.storage.tigris.dev" || hostname.endsWith(".fly.storage.tigris.dev")
}

/** @returns {boolean} false if upload was aborted (caller must skip xhr) */
function validatePresignedPostUrl(url, entry) {
    if (!url || typeof url !== "string") {
        console.error("S3 upload: missing presign URL from server (entry.meta.url)")
        entry.error()
        return false
    }
    let parsed
    try {
        parsed = new URL(url)
    } catch (e) {
        console.error("S3 upload: invalid presign URL", url, e)
        entry.error()
        return false
    }
    if (s3UseCustomDomainFromPage() && isTigrisFlyStorageUploadHost(parsed.hostname)) {
        console.error(
            "S3 upload: page expects custom S3 domains (data-s3-use-custom-domain) but presign URL is a Tigris virtual host. Fix server S3Config / Fly env (S3_*_PUBLIC_BASE_URL, S3_USE_CUSTOM_DOMAIN, runtime.exs).",
            url
        )
        entry.error()
        return false
    }
    return true
}

Uploaders.S3 = function(entries, onViewError) {
    entries.forEach(entry => {
        let formData = new FormData()
        let { url, fields } = entry.meta
        if (!validatePresignedPostUrl(url, entry)) {
            return
        }
        Object.entries(fields).forEach(([key, val]) => formData.append(key, val))
        formData.append("file", entry.file)
        let xhr = new XMLHttpRequest()
        onViewError(() => xhr.abort())
        // LiveView 1.2.10+: abort the S3 POST when the user cancels this entry
        // or navigates away (entry.onCancel / external upload cancel).
        entry.onCancel(() => xhr.abort())

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