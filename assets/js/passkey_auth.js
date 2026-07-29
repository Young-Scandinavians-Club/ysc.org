/**
 * PasskeyAuth Hook
 *
 * Handles WebAuthn/Passkey authentication using the browser's native API.
 * Also handles device detection (iOS mobile) and passkey support detection.
 * Uses builtin browser functionality (parseRequestOptionsFromJSON) when available.
 */
import { pushEventIfConnected, pushEventToIfConnected } from "./live_view_safe_push";

const PasskeyAuth = {
    detectAndPushSupport() {
        const userAgent = navigator.userAgent;
        const isIOSMobile = /iPhone|iPad|iPod/.test(userAgent);

        if (isIOSMobile) {
            pushEventIfConnected(this, "device_detected", { device: "ios_mobile" });
        }

        const isPasskeySupported = typeof window.PublicKeyCredential !== "undefined";

        pushEventIfConnected(this, "passkey_support_detected", {
            supported: isPasskeySupported
        });

        pushEventIfConnected(this, "user_agent_received", { user_agent: userAgent });
    },

    mounted() {
        this.detectAndPushSupport();

        const isPasskeySupported = typeof window.PublicKeyCredential !== "undefined";

        // If WebAuthn is not supported, return early
        if (!isPasskeySupported) {
            return;
        }

        // Listen for authentication challenge from LiveView
        this.handleEvent("create_authentication_challenge", async ({ options }) => {
            try {
                // Add breadcrumb for debugging
                if (window.Sentry) {
                    window.Sentry.addBreadcrumb({
                        category: "passkey",
                        message: "Starting authentication challenge",
                        level: "info",
                        data: {
                            hasChallenge: !!options?.challenge,
                            hasRpId: !!(options?.rpId || options?.rp_id),
                            userAgent: navigator.userAgent
                        }
                    });
                }

                // Check if browser supports JSON-based WebAuthn API
                const jsonWebAuthnSupport = !!window.PublicKeyCredential?.parseRequestOptionsFromJSON;

                let credential;

                if (jsonWebAuthnSupport) {
                    // Use modern JSON-based API (Chrome 108+, Safari 16.4+, Firefox 119+)
                    // parseRequestOptionsFromJSON expects { publicKey: options } format
                    // The options should have camelCase keys (challenge, rpId, userVerification)
                    const publicKeyOptions = {
                        challenge: options?.challenge,
                        rpId: options?.rpId || options?.rp_id,
                        timeout: options?.timeout,
                        userVerification: options?.userVerification || options?.user_verification || "preferred"
                        // Intentionally omitting allowCredentials for discoverable credentials
                    };
                    
                    // parseRequestOptionsFromJSON expects { publicKey: { challenge, rpId, ... } }
                    const parseInput = { publicKey: publicKeyOptions };
                    
                    if (!parseInput.publicKey?.challenge) {
                        const errorMsg = "Challenge is required but was not provided";
                        console.error("[PasskeyAuth] CRITICAL: Challenge is missing from parseInput!", {
                            parseInput: parseInput,
                            publicKeyOptions: publicKeyOptions,
                            originalOptions: options
                        });
                        
                        if (window.Sentry) {
                            window.Sentry.captureException(new Error(errorMsg), {
                                tags: {
                                    component: "passkey_auth",
                                    operation: "authentication",
                                    error_type: "missing_challenge"
                                },
                                extra: {
                                    parseInput,
                                    publicKeyOptions,
                                    originalOptions: options
                                }
                            });
                        }
                        
                        throw new Error(errorMsg);
                    }
                    
                    // Try parseRequestOptionsFromJSON - if it fails or produces empty challenge, fall back to manual conversion
                    let publicKey;
                    try {
                        publicKey = PublicKeyCredential.parseRequestOptionsFromJSON(parseInput);
                        
                        // Check if challenge was properly converted (should be non-empty ArrayBuffer)
                        if (!publicKey.challenge || publicKey.challenge.byteLength === 0) {
                            throw new Error("Empty challenge from parseRequestOptionsFromJSON");
                        }
                        
                        // Also check if rpId is missing
                        if (!publicKey.rpId) {
                            throw new Error("Missing rpId from parseRequestOptionsFromJSON");
                        }
                    } catch (parseError) {
                        console.warn("[PasskeyAuth] parseRequestOptionsFromJSON failed, falling back to manual conversion", parseError);
                        
                        if (window.Sentry) {
                            window.Sentry.addBreadcrumb({
                                category: "passkey",
                                message: "Fallback to manual challenge conversion",
                                level: "warning",
                                data: {
                                    error: parseError.message,
                                    challengeLength: publicKeyOptions.challenge?.length
                                }
                            });
                        }
                        
                        // Fallback: manually convert challenge from base64url to ArrayBuffer
                        publicKey = {
                            challenge: base64UrlToArrayBuffer(publicKeyOptions.challenge),
                            rpId: publicKeyOptions.rpId,
                            timeout: publicKeyOptions.timeout,
                            userVerification: publicKeyOptions.userVerification
                        };
                    }
                    
                    credential = await navigator.credentials.get({ publicKey });
                } else {
                    // Fallback to traditional API (requires manual Base64 encoding/decoding)
                    if (window.Sentry) {
                        window.Sentry.addBreadcrumb({
                            category: "passkey",
                            message: "Using legacy WebAuthn API (no JSON support)",
                            level: "info"
                        });
                    }
                    
                    const publicKey = {
                        ...options,
                        challenge: base64UrlToArrayBuffer(options.challenge)
                    };

                    // Only include allowCredentials if it exists (non-discoverable mode)
                    if (options.allowCredentials && options.allowCredentials.length > 0) {
                        publicKey.allowCredentials = options.allowCredentials.map(cred => ({
                            ...cred,
                            id: base64UrlToArrayBuffer(cred.id)
                        }));
                    }

                    credential = await navigator.credentials.get({ publicKey });

                    // Convert ArrayBuffers back to base64url strings
                    if (credential) {
                        credential = {
                            id: credential.id,
                            rawId: arrayBufferToBase64Url(credential.rawId),
                            response: {
                                authenticatorData: arrayBufferToBase64Url(credential.response.authenticatorData),
                                clientDataJSON: arrayBufferToBase64Url(credential.response.clientDataJSON),
                                signature: arrayBufferToBase64Url(credential.response.signature),
                                userHandle: credential.response.userHandle ? arrayBufferToBase64Url(credential.response.userHandle) : null
                            },
                            type: credential.type
                        };
                    }
                }

                if (credential) {
                    // Convert credential to JSON format for transmission
                    const credentialJson = jsonWebAuthnSupport && credential.toJSON ?
                        credential.toJSON() :
                        credential;

                    if (window.Sentry) {
                        window.Sentry.addBreadcrumb({
                            category: "passkey",
                            message: "Authentication credential obtained successfully",
                            level: "info"
                        });
                    }

                    // Push the result to the component if data-push-to is set,
                    // otherwise fall back to the LiveView (e.g. login page).
                    this.pushPasskeyEvent("verify_authentication", credentialJson);
                } else {
                    const errorMsg = "No credential returned from navigator.credentials.get";
                    console.error("[PasskeyAuth]", errorMsg);
                    
                    if (window.Sentry) {
                        window.Sentry.captureException(new Error(errorMsg), {
                            tags: {
                                component: "passkey_auth",
                                operation: "authentication",
                                error_type: "no_credential"
                            }
                        });
                    }
                }
            } catch (error) {
                // Expected UX outcomes: user cancel/timeout, or browser/platform
                // lacking discoverable (resident) credential support.
                const isExpectedAuthError = error.name === "NotAllowedError" ||
                    error.name === "AbortError" ||
                    error.name === "NotSupportedError";

                if (isExpectedAuthError) {
                    console.info("[PasskeyAuth] Authentication ended without completion", {
                        name: error.name,
                        message: error.message
                    });
                } else {
                    console.error("[PasskeyAuth] Passkey authentication failed", error);

                    if (window.Sentry) {
                        window.Sentry.captureException(error, {
                            tags: {
                                component: "passkey_auth",
                                operation: "authentication",
                                error_name: error.name,
                                browser: navigator.userAgent.match(/Firefox|Chrome|Safari|Edge/)?.[0] || "unknown"
                            },
                            extra: {
                                errorMessage: error.message,
                                errorStack: error.stack,
                                userAgent: navigator.userAgent,
                                hasPublicKeyCredential: typeof window.PublicKeyCredential !== "undefined",
                                hasParseRequestOptions: !!window.PublicKeyCredential?.parseRequestOptionsFromJSON
                            }
                        });
                    }
                }

                this.pushPasskeyEvent("passkey_auth_error", {
                    error: error.name || "UnknownError",
                    message: error.message || "Authentication failed"
                });
            }
        });

        // Listen for registration challenge from LiveView
        this.handleEvent("create_registration_challenge", async (payload) => {
            const options = payload?.options || payload;

            if (!options) {
                const errorMsg = "No options provided in create_registration_challenge event";
                console.error("[PasskeyAuth]", errorMsg, {
                    payload: payload
                });
                
                if (window.Sentry) {
                    window.Sentry.captureException(new Error(errorMsg), {
                        tags: {
                            component: "passkey_auth",
                            operation: "registration",
                            error_type: "missing_options"
                        },
                        extra: {
                            payload
                        }
                    });
                }
                
                // Push error event to LiveView so it doesn't hang
                this.pushPasskeyEvent("passkey_registration_error", {
                    error: "ConfigurationError",
                    message: errorMsg
                });
                return;
            }

            try {
                // Add breadcrumb for debugging
                if (window.Sentry) {
                    window.Sentry.addBreadcrumb({
                        category: "passkey",
                        message: "Starting registration challenge",
                        level: "info",
                        data: {
                            hasChallenge: !!options?.challenge,
                            hasRp: !!options?.rp,
                            hasUser: !!options?.user,
                            userAgent: navigator.userAgent
                        }
                    });
                }

                // Check if browser supports JSON-based WebAuthn API
                const jsonWebAuthnSupport = !!window.PublicKeyCredential?.parseCreationOptionsFromJSON;

                let credential;

                if (jsonWebAuthnSupport) {
                    // Verify all required fields are present
                    if (!options?.challenge) {
                        const errorMsg = "Challenge is required but was not provided";
                        console.error("[PasskeyAuth]", errorMsg);
                        
                        if (window.Sentry) {
                            window.Sentry.captureException(new Error(errorMsg), {
                                tags: {
                                    component: "passkey_auth",
                                    operation: "registration",
                                    error_type: "missing_challenge"
                                },
                                extra: { options }
                            });
                        }
                        
                        throw new Error(errorMsg);
                    }
                    if (!options?.rp) {
                        const errorMsg = "RP is required but was not provided";
                        console.error("[PasskeyAuth]", errorMsg);
                        
                        if (window.Sentry) {
                            window.Sentry.captureException(new Error(errorMsg), {
                                tags: {
                                    component: "passkey_auth",
                                    operation: "registration",
                                    error_type: "missing_rp"
                                },
                                extra: { options }
                            });
                        }
                        
                        throw new Error(errorMsg);
                    }
                    if (!options?.user) {
                        const errorMsg = "User is required but was not provided";
                        console.error("[PasskeyAuth]", errorMsg);
                        
                        if (window.Sentry) {
                            window.Sentry.captureException(new Error(errorMsg), {
                                tags: {
                                    component: "passkey_auth",
                                    operation: "registration",
                                    error_type: "missing_user"
                                },
                                extra: { options }
                            });
                        }
                        
                        throw new Error(errorMsg);
                    }
                    
                    // Use modern JSON-based WebAuthn API (Chrome 108+, Safari 16.4+, Firefox 119+)
                    // parseCreationOptionsFromJSON expects the options object directly (not wrapped in { publicKey: ... })
                    // It returns a PublicKeyCredentialCreationOptions object which is then used in navigator.credentials.create({ publicKey: ... })
                    // Try parseCreationOptionsFromJSON - if it fails or produces empty challenge, fall back to manual conversion
                    let publicKey;
                    try {
                        publicKey = PublicKeyCredential.parseCreationOptionsFromJSON(options);
                        
                        // Check if challenge was properly converted (should be non-empty ArrayBuffer)
                        if (!publicKey.challenge || publicKey.challenge.byteLength === 0) {
                            throw new Error("Empty challenge from parseCreationOptionsFromJSON");
                        }
                        
                        // Also check if user.id is missing or empty
                        if (!publicKey.user?.id || publicKey.user.id.byteLength === 0) {
                            throw new Error("Missing or empty user.id from parseCreationOptionsFromJSON");
                        }
                    } catch (parseError) {
                        console.warn("[PasskeyAuth] parseCreationOptionsFromJSON failed, falling back to manual conversion", parseError);
                        
                        if (window.Sentry) {
                            window.Sentry.addBreadcrumb({
                                category: "passkey",
                                message: "Fallback to manual challenge conversion",
                                level: "warning",
                                data: {
                                    error: parseError.message,
                                    challengeLength: options.challenge?.length,
                                    userIdLength: options.user?.id?.length
                                }
                            });
                        }
                        
                        // Fallback: manually convert challenge and user.id from base64url to ArrayBuffer
                        publicKey = {
                            challenge: base64UrlToArrayBuffer(options.challenge),
                            rp: options.rp,
                            user: {
                                ...options.user,
                                id: base64UrlToArrayBuffer(options.user.id)
                            },
                            pubKeyCredParams: options.pubKeyCredParams,
                            timeout: options.timeout,
                            authenticatorSelection: options.authenticatorSelection
                        };
                    }
                    
                    credential = await navigator.credentials.create({ publicKey });
                } else {
                    // Fallback to traditional API (requires manual Base64 encoding/decoding)
                    if (window.Sentry) {
                        window.Sentry.addBreadcrumb({
                            category: "passkey",
                            message: "Using legacy WebAuthn API (no JSON support)",
                            level: "info"
                        });
                    }
                    
                    // Convert base64url strings to ArrayBuffer
                    const publicKey = {
                        ...options,
                        challenge: base64UrlToArrayBuffer(options.challenge),
                        user: {
                            ...options.user,
                            id: base64UrlToArrayBuffer(options.user.id)
                        }
                    };

                    credential = await navigator.credentials.create({ publicKey });

                    // Convert ArrayBuffers back to base64url strings
                    if (credential) {
                        credential = {
                            id: credential.id,
                            rawId: arrayBufferToBase64Url(credential.rawId),
                            response: {
                                attestationObject: arrayBufferToBase64Url(credential.response.attestationObject),
                                clientDataJSON: arrayBufferToBase64Url(credential.response.clientDataJSON)
                            },
                            type: credential.type
                        };
                    }
                }

                if (credential) {
                    
                    // Convert credential to JSON format for transmission
                    const credentialJson = jsonWebAuthnSupport && credential.toJSON ?
                        credential.toJSON() :
                        credential;

                    if (window.Sentry) {
                        window.Sentry.addBreadcrumb({
                            category: "passkey",
                            message: "Registration credential obtained successfully",
                            level: "info"
                        });
                    }

                    // Push the result back to the LiveView
                    this.pushPasskeyEvent("verify_registration", credentialJson);
                } else {
                    const errorMsg = "No credential returned from navigator.credentials.create";
                    console.error("[PasskeyAuth]", errorMsg);
                    
                    if (window.Sentry) {
                        window.Sentry.captureException(new Error(errorMsg), {
                            tags: {
                                component: "passkey_auth",
                                operation: "registration",
                                error_type: "no_credential"
                            }
                        });
                    }
                }
            } catch (error) {
                const isExpectedAuthError = error.name === "NotAllowedError" ||
                    error.name === "AbortError" ||
                    error.name === "NotSupportedError";

                if (isExpectedAuthError) {
                    console.info("[PasskeyAuth] Registration ended without completion", {
                        name: error.name,
                        message: error.message
                    });
                } else {
                    console.error("[PasskeyAuth] Passkey registration failed", error);

                    if (window.Sentry) {
                        window.Sentry.captureException(error, {
                            tags: {
                                component: "passkey_auth",
                                operation: "registration",
                                error_name: error.name,
                                browser: navigator.userAgent.match(/Firefox|Chrome|Safari|Edge/)?.[0] || "unknown"
                            },
                            extra: {
                                errorMessage: error.message,
                                errorStack: error.stack,
                                userAgent: navigator.userAgent,
                                hasPublicKeyCredential: typeof window.PublicKeyCredential !== "undefined",
                                hasParseCreationOptions: !!window.PublicKeyCredential?.parseCreationOptionsFromJSON
                            }
                        });
                    }
                }

                this.pushPasskeyEvent("passkey_registration_error", {
                    error: error.name || "UnknownError",
                    message: error.message || "Registration failed"
                });
            }
        });
    },

    /**
     * Push an event to the component identified by `data-push-to` if present,
     * otherwise push to the root LiveView. This lets the ReauthComponent receive
     * verify_authentication and passkey_auth_error directly without the parent
     * LiveView acting as a relay.
     */
    pushPasskeyEvent(event, payload) {
        const target = this.el.dataset.pushTo;
        if (target) {
            pushEventToIfConnected(this, `#${target}`, event, payload);
        } else {
            pushEventIfConnected(this, event, payload);
        }
    },

    reconnected() {
        // Re-send support/device detection after a LiveView reconnect. When the
        // WebSocket drops and reconnects, the server mounts fresh and resets
        // passkey_supported to false, so we must push the status again.
        this.detectAndPushSupport();
    }
};

// Helper functions for Base64 URL encoding/decoding (for older browsers)
function base64UrlToArrayBuffer(base64url) {
    try {
        // Convert base64url to base64
        let base64 = base64url.replace(/-/g, '+').replace(/_/g, '/');

        // Add padding if needed
        while (base64.length % 4) {
            base64 += '=';
        }

        // Decode base64 to binary string
        const binaryString = atob(base64);

        // Convert binary string to ArrayBuffer
        const bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i);
        }

        return bytes.buffer;
    } catch (error) {
        console.error("[PasskeyAuth] Error converting base64url to ArrayBuffer", {
            error: error.message,
            input: base64url,
            inputType: typeof base64url,
            inputLength: base64url?.length
        });
        
        if (window.Sentry) {
            window.Sentry.captureException(error, {
                tags: {
                    component: "passkey_auth",
                    function: "base64UrlToArrayBuffer"
                },
                extra: {
                    input: base64url,
                    inputType: typeof base64url,
                    inputLength: base64url?.length
                }
            });
        }
        
        throw error;
    }
}

function arrayBufferToBase64Url(arrayBuffer) {
    try {
        // Convert ArrayBuffer to Uint8Array
        const bytes = new Uint8Array(arrayBuffer);

        // Convert to binary string
        let binary = '';
        for (let i = 0; i < bytes.length; i++) {
            binary += String.fromCharCode(bytes[i]);
        }

        // Encode to base64
        const base64 = btoa(binary);

        // Convert base64 to base64url
        return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    } catch (error) {
        console.error("[PasskeyAuth] Error converting ArrayBuffer to base64url", {
            error: error.message,
            inputType: typeof arrayBuffer,
            inputByteLength: arrayBuffer?.byteLength
        });
        
        if (window.Sentry) {
            window.Sentry.captureException(error, {
                tags: {
                    component: "passkey_auth",
                    function: "arrayBufferToBase64Url"
                },
                extra: {
                    inputType: typeof arrayBuffer,
                    inputByteLength: arrayBuffer?.byteLength
                }
            });
        }
        
        throw error;
    }
}


export default PasskeyAuth;