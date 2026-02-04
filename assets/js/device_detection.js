const DeviceDetection = {
    mounted() {
        // Detect if device is an iPhone or iPad (iOS mobile device)
        const isIOSMobile = /iPhone|iPad|iPod/.test(navigator.userAgent);

        if (isIOSMobile) {
            // Send event to LiveView to update the assign
            this.pushEvent("device_detected", { device: "ios_mobile" });
        }

        // Check if WebAuthn/Passkey is supported
        const isPasskeySupported = typeof window.PublicKeyCredential !== "undefined";

        // Send event to LiveView with passkey support status
        this.pushEvent("passkey_support_detected", { supported: isPasskeySupported });
    }
};

export default DeviceDetection;