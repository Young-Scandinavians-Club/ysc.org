/**
 * PasskeyAuth Hook
 *
 * Handles WebAuthn/Passkey authentication using the browser's native API.
 * Also handles device detection (iOS mobile) and passkey support detection.
 * Uses builtin browser functionality (parseRequestOptionsFromJSON) when available.
 */
const PasskeyAuth = {
    mounted() {
        // Device detection: Detect if device is an iPhone or iPad (iOS mobile device)
        const userAgent = navigator.userAgent;
        const isIOSMobile = /iPhone|iPad|iPod/.test(userAgent);

        if (isIOSMobile) {
            this.pushEvent("device_detected", { device: "ios_mobile" });
        }

        // Check if WebAuthn/Passkey is supported
        const hasPublicKeyCredential = typeof window.PublicKeyCredential !== "undefined";
        const isPasskeySupported = hasPublicKeyCredential;

        // Send event to LiveView with passkey support status
        try {
            this.pushEvent("passkey_support_detected", { supported: isPasskeySupported });
        } catch (error) {
            console.error("[PasskeyAuth] Error pushing passkey_support_detected event", error);
        }

        // Send user agent to LiveView for device nickname generation
        try {
            this.pushEvent("user_agent_received", { user_agent: userAgent });
        } catch (error) {
            console.error("[PasskeyAuth] Error pushing user_agent_received event", error);
        }

        // If WebAuthn is not supported, return early
        if (!isPasskeySupported) {
            return;
        }

        // Listen for authentication challenge from LiveView
        this.handleEvent("create_authentication_challenge", async ({ options }) => {
            try {
                // Check if browser supports JSON-based WebAuthn API
                const jsonWebAuthnSupport = !!window.PublicKeyCredential?.parseRequestOptionsFromJSON;

                let credential;

                if (jsonWebAuthnSupport) {
                    console.log("[PasskeyAuth] Using modern JSON-based WebAuthn API");
                    console.log("[PasskeyAuth] Options before parsing", {
                        options: options,
                        hasChallenge: !!options?.challenge,
                        challengeValue: options?.challenge,
                        challengeLength: options?.challenge?.length,
                        challengeType: typeof options?.challenge,
                        rpId: options?.rpId || options?.rp_id,
                        timeout: options?.timeout,
                        userVerification: options?.userVerification || options?.user_verification,
                        allKeys: Object.keys(options || {})
                    });
                    
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
                    
                    console.log("[PasskeyAuth] Prepared publicKeyOptions for parseRequestOptionsFromJSON", {
                        hasChallenge: !!publicKeyOptions.challenge,
                        challengeValue: publicKeyOptions.challenge,
                        challengeLength: publicKeyOptions.challenge?.length,
                        challengeType: typeof publicKeyOptions.challenge,
                        rpId: publicKeyOptions.rpId,
                        userVerification: publicKeyOptions.userVerification,
                        fullOptions: JSON.stringify(publicKeyOptions)
                    });
                    
                    // parseRequestOptionsFromJSON expects { publicKey: { challenge, rpId, ... } }
                    const parseInput = { publicKey: publicKeyOptions };
                    console.log("[PasskeyAuth] Input to parseRequestOptionsFromJSON", {
                        hasPublicKey: !!parseInput.publicKey,
                        hasChallenge: !!parseInput.publicKey?.challenge,
                        challengeValue: parseInput.publicKey?.challenge,
                        challengeLength: parseInput.publicKey?.challenge?.length,
                        challengeType: typeof parseInput.publicKey?.challenge,
                        fullInput: JSON.stringify(parseInput, null, 2)
                    });
                    
                    if (!parseInput.publicKey?.challenge) {
                        console.error("[PasskeyAuth] CRITICAL: Challenge is missing from parseInput!", {
                            parseInput: parseInput,
                            publicKeyOptions: publicKeyOptions,
                            originalOptions: options
                        });
                        throw new Error("Challenge is required but was not provided");
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

                    // Push the result back to the LiveView
                    this.pushEvent("verify_authentication", credentialJson);
                }
            } catch (error) {
                console.error("[PasskeyAuth] Passkey authentication failed", error);

                // Push error event to LiveView
                this.pushEvent("passkey_auth_error", {
                    error: error.name || "UnknownError",
                    message: error.message || "Authentication failed"
                });
            }
        });

        console.log("[PasskeyAuth] Setting up registration challenge handler");

        // Listen for registration challenge from LiveView
        this.handleEvent("create_registration_challenge", async (payload) => {
            console.log("[PasskeyAuth] REGISTRATION HANDLER CALLED!", payload);
            console.log("[PasskeyAuth] create_registration_challenge event received - RAW PAYLOAD", payload);
            
            const options = payload?.options || payload;
            
            console.log("[PasskeyAuth] create_registration_challenge event received", {
                payload: payload,
                options: options,
                optionsKeys: options ? Object.keys(options) : null,
                hasChallenge: !!options?.challenge,
                challengeValue: options?.challenge,
                challengeType: typeof options?.challenge,
                challengeLength: options?.challenge?.length,
                hasUser: !!options?.user,
                hasRp: !!options?.rp,
                elementId: this.el?.id,
                hookName: "PasskeyAuth"
            });

            if (!options) {
                console.error("[PasskeyAuth] No options provided in create_registration_challenge event", {
                    payload: payload
                });
                return;
            }

            try {
                // Check if browser supports JSON-based WebAuthn API
                const jsonWebAuthnSupport = !!window.PublicKeyCredential?.parseCreationOptionsFromJSON;
                
                console.log("[PasskeyAuth] Browser capabilities for registration", {
                    jsonWebAuthnSupport: jsonWebAuthnSupport,
                    hasParseCreationOptionsFromJSON: !!window.PublicKeyCredential?.parseCreationOptionsFromJSON,
                    hasToJSON: !!window.PublicKeyCredential?.prototype?.toJSON
                });

                let credential;

                if (jsonWebAuthnSupport) {
                    console.log("[PasskeyAuth] Using modern JSON-based WebAuthn API for registration");
                    console.log("[PasskeyAuth] Options before parsing:", JSON.stringify(options, null, 2));
                    console.log("[PasskeyAuth] Challenge value:", options?.challenge);
                    console.log("[PasskeyAuth] Challenge type:", typeof options?.challenge);
                    console.log("[PasskeyAuth] Challenge length:", options?.challenge?.length);
                    
                    // Verify all required fields are present
                    if (!options?.challenge) {
                        console.error("[PasskeyAuth] Challenge is missing from options!");
                        throw new Error("Challenge is required but was not provided");
                    }
                    if (!options?.rp) {
                        console.error("[PasskeyAuth] RP is missing from options!");
                        throw new Error("RP is required but was not provided");
                    }
                    if (!options?.user) {
                        console.error("[PasskeyAuth] User is missing from options!");
                        throw new Error("User is required but was not provided");
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
                    console.log("[PasskeyAuth] Using fallback traditional WebAuthn API for registration");
                    // Fallback to traditional API (requires manual Base64 encoding/decoding)
                    // Convert base64url strings to ArrayBuffer
                    console.log("[PasskeyAuth] Converting challenge to ArrayBuffer", {
                        challengeLength: options.challenge?.length,
                        challengePreview: options.challenge?.substring(0, 20)
                    });
                    
                    const publicKey = {
                        ...options,
                        challenge: base64UrlToArrayBuffer(options.challenge),
                        user: {
                            ...options.user,
                            id: base64UrlToArrayBuffer(options.user.id)
                        }
                    };

                    console.log("[PasskeyAuth] Built publicKey object for registration", {
                        hasChallenge: !!publicKey.challenge,
                        challengeType: publicKey.challenge?.constructor?.name,
                        hasUser: !!publicKey.user,
                        hasRp: !!publicKey.rp
                    });

                    console.log("[PasskeyAuth] Calling navigator.credentials.create() with fallback API...");
                    credential = await navigator.credentials.create({ publicKey });
                    console.log("[PasskeyAuth] navigator.credentials.create() completed (fallback)", {
                        hasCredential: !!credential,
                        credentialId: credential?.id,
                        credentialType: credential?.type
                    });

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
                    console.log("[PasskeyAuth] Processing credential for transmission", {
                        jsonWebAuthnSupport: jsonWebAuthnSupport,
                        hasToJSON: jsonWebAuthnSupport && typeof credential.toJSON === "function"
                    });
                    
                    // Convert credential to JSON format for transmission
                    const credentialJson = jsonWebAuthnSupport && credential.toJSON ?
                        credential.toJSON() :
                        credential;

                    // Push the result back to the LiveView
                    this.pushEvent("verify_registration", credentialJson);
                }
            } catch (error) {
                console.error("[PasskeyAuth] Passkey registration failed", error);

                // Push error event to LiveView
                this.pushEvent("passkey_registration_error", {
                    error: error.name || "UnknownError",
                    message: error.message || "Registration failed"
                });
            }
        });
    }
};

// Helper functions for Base64 URL encoding/decoding (for older browsers)
function base64UrlToArrayBuffer(base64url) {
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
}

function arrayBufferToBase64Url(arrayBuffer) {
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
}


export default PasskeyAuth;