# Offline macOS Application

A minimal macOS SwiftUI app, protected with licenses by [Keyforge](https://keyforge.dev). License validations are done offline, by verifying signed JWTs. No backend is needed, all license operations are done through the Keyforge public API.

## How it works

1. **Activation** — The user enters a license key. The app sends it to Keyforge with a device identifier and receives a signed JWT.
2. **Offline Verification** — On every launch, the JWT is verified locally using the ES256 public key.
3. **Token Refresh** — When the JWT is near expiry (within 3 days), the app fetches a fresh token. Manual refresh is also available.

> [!NOTE]
> Perpetual fallback access is also supported natively. If it's enabled on a product and a timed license expires, the app continues granting limited access.

## Setup

1. Go to the [Keyforge dashboard](https://keyforge.dev/dashboard), create a product, and enable **License Token**.
2. Copy your **Product ID** and **ES256 Public Key**.
3. Open `LicenseManager.swift` and replace the placeholders in `KeyforgeConfig`:

```swift
enum KeyforgeConfig {
    static let productId = "YOUR_PRODUCT_ID"

    static let publicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    YOUR_PUBLIC_KEY_HERE
    -----END PUBLIC KEY-----
    """
}
```

4. Enable outgoing network connections in the App Sandbox:
   > Xcode → project → **Offline Example App** target → **Signing & Capabilities** → **App Sandbox** → check **Outgoing Connections (Client)**

5. Build and run. Enter a license key to activate the app, subsequent launches verify offline.

## Project structure

| File | Purpose |
|---|---|
| `LicenseManager.swift` | Activation, offline JWT verification, token refresh, state management. |
| `ActivationView.swift` | License key input form. |
| `SuccessView.swift` | Licensed state display with status, expiration, and fallback indicator. |
| `ContentView.swift` | Routes between activation and success views. |

## Implementation details

- **Device ID** — Uses `IOPlatformUUID` for a stable hardware identifier, with a Keychain-stored UUID fallback.
- **JWT Verification** — `CryptoKit` (`P256.Signing.PublicKey`) verifies the ES256 signature, expiration, product ID, and device claims.
- **Storage** — License key, token, and device ID are stored in the macOS Keychain.

