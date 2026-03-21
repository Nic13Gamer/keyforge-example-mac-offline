//
//  LicenseManager.swift
//  Offline Example
//
//  A license manager that handles Keyforge license activation and offline
//  validation using signed JWT license tokens (ES256).
//

import Foundation
import CryptoKit

// MARK: - Configuration

enum KeyforgeConfig {
    // TODO: Replace with your Keyforge product ID (found in your dashboard).
    static let productId = "p_wh014v84u8xvejz5bcp3esgw"

    // TODO: Replace with the ES256 public key from your Keyforge dashboard.
    static let publicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAELHprQskwqLK+KzKMHJ0m9BCUAU/W
    t6APEEoglKFI7nIJWP8vZ/KtVu0ipkpRM2CHB0DH+OJeJMErqyJOq+oVag==
    -----END PUBLIC KEY-----
    """
    
//    // TODO: Replace with your Keyforge product ID (found in your dashboard).
//    static let productId = "YOUR_PRODUCT_ID"
//
//    // TODO: Replace with the ES256 public key from your Keyforge dashboard.
//    static let publicKeyPEM = """
//    -----BEGIN PUBLIC KEY-----
//    YOUR_PUBLIC_KEY_HERE
//    -----END PUBLIC KEY-----
//    """

    static let activateURL = URL(string: "https://keyforge.dev/api/v1/public/licenses/activate")!
    static let refreshTokenURL = URL(string: "https://keyforge.dev/api/v1/public/licenses/token")!
}

// MARK: - License Manager

@MainActor
@Observable
final class LicenseManager {

    // MARK: Published State

    var isCheckingLicense = true
    var isLicensed = false
    var licenseStatus: String = ""
    var licenseEmail: String?
    var licenseExpiresAt: Date?
    var isLoading = false
    var errorMessage: String?

    // MARK: Private

    private let defaults = UserDefaults.standard

    private var storedLicenseKey: String? {
        get { defaults.string(forKey: "keyforge_license_key") }
        set { defaults.set(newValue, forKey: "keyforge_license_key") }
    }

    private var storedToken: String? {
        get { defaults.string(forKey: "keyforge_license_token") }
        set { defaults.set(newValue, forKey: "keyforge_license_token") }
    }

    private var storedDeviceId: String? {
        get { defaults.string(forKey: "keyforge_device_id") }
        set { defaults.set(newValue, forKey: "keyforge_device_id") }
    }

    // MARK: - Device Identifier

    /// Returns a stable device identifier using IOPlatformUUID, or falls back
    /// to a generated UUID stored in UserDefaults.
    private var deviceIdentifier: String {
        if let existing = storedDeviceId {
            return existing
        }

        var id = UUID().uuidString

        // Attempt to read the hardware UUID from the I/O Registry.
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        if service != IO_OBJECT_NULL {
            if let uuidRef = IORegistryEntryCreateCFProperty(
                service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String {
                id = uuidRef
            }
            IOObjectRelease(service)
        }

        storedDeviceId = id
        return id
    }

    private var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }

    // MARK: - Startup Check

    /// Call this on app launch. Validates the stored license token offline.
    /// If the token is missing, expired, or invalid the user must re-activate.
    func checkLicense() async {
        isCheckingLicense = true
        defer { isCheckingLicense = false }

        guard let token = storedToken else {
            isLicensed = false
            return
        }

        let result = verifyTokenOffline(token)
        if result.isValid {
            applyTokenClaims(result)

            // If the token is approaching expiration, try refreshing it
            // in the background (requires network, but non-blocking).
            if let exp = result.expiresAt, exp.timeIntervalSinceNow < 3 * 24 * 60 * 60 {
                await refreshToken()
            }
        } else {
            // Token invalid or expired — user needs to re-activate.
            isLicensed = false
        }
    }

    // MARK: - Online Activation

    /// Activates a license key with Keyforge and stores the returned token.
    func activate(licenseKey: String) async {
        isLoading = true
        errorMessage = nil

        let body: [String: Any] = [
            "licenseKey": licenseKey.trimmingCharacters(in: .whitespacesAndNewlines),
            "deviceIdentifier": deviceIdentifier,
            "deviceName": deviceName,
            "productId": KeyforgeConfig.productId
        ]

        do {
            let (data, response) = try await postJSON(
                url: KeyforgeConfig.activateURL,
                body: body
            )

            guard let http = response as? HTTPURLResponse else {
                throw LicenseError.invalidResponse
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            if http.statusCode == 200, json["isValid"] as? Bool == true {
                storedLicenseKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

                // Store the JWT license token and verify it before
                // granting access — reject if the token is invalid.
                guard let token = json["token"] as? String else {
                    throw LicenseError.serverError("No license token returned. Ensure token-based licensing is enabled for this product.")
                }

                storedToken = token
                let result = verifyTokenOffline(token)

                guard result.isValid else {
                    storedToken = nil
                    storedLicenseKey = nil
                    throw LicenseError.serverError("License token verification failed. The token signature is invalid.")
                }

                applyTokenClaims(result)
            } else {
                let errorObj = json["error"] as? [String: Any]
                let message = errorObj?["message"] as? String ?? "Activation failed."
                throw LicenseError.serverError(message)
            }
        } catch let error as LicenseError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Token Refresh

    /// Refreshes the license token. Call this when the token is approaching
    /// expiration (e.g. 3 days before `exp`).
    func refreshToken() async {
        guard let key = storedLicenseKey else { return }

        let body: [String: Any] = [
            "licenseKey": key,
            "deviceIdentifier": deviceIdentifier,
            "productId": KeyforgeConfig.productId
        ]

        do {
            let (data, response) = try await postJSON(
                url: KeyforgeConfig.refreshTokenURL,
                body: body
            )

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if let token = json["token"] as? String {
                storedToken = token

                // Re-verify the new token so the UI reflects updated claims.
                let result = verifyTokenOffline(token)
                if result.isValid {
                    applyTokenClaims(result)
                }
            }
        } catch {
            // Refresh failed — the existing token is still usable until it expires.
        }
    }

    // MARK: - Deactivate / Log Out

    func deactivate() {
        storedLicenseKey = nil
        storedToken = nil
        // Note: deviceIdentifier is intentionally kept — it should remain
        // stable across activations so Keyforge tracks one device, not many.
        isLicensed = false
        licenseStatus = ""
        licenseEmail = nil
        licenseExpiresAt = nil
    }

    // MARK: - Offline JWT Verification (ES256)

    private struct TokenResult {
        var isValid = false
        var status: String = ""
        var email: String?
        var expiresAt: Date?
    }

    /// Verifies the JWT license token offline using the ES256 public key.
    private func verifyTokenOffline(_ token: String) -> TokenResult {
        var result = TokenResult()

        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return result }

        let headerAndPayload = "\(parts[0]).\(parts[1])"
        guard let signatureData = base64URLDecode(String(parts[2])),
              let payloadData = base64URLDecode(String(parts[1])) else {
            return result
        }

        // Verify signature using ES256 (P-256).
        guard let publicKey = loadES256PublicKey() else {
            return result
        }

        let signature: P256.Signing.ECDSASignature
        do {
            signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        } catch {
            return result
        }

        let messageData = Data(headerAndPayload.utf8)
        let isSignatureValid = publicKey.isValidSignature(
            signature,
            for: SHA256.hash(data: messageData)
        )

        guard isSignatureValid else { return result }

        // Parse the payload.
        guard let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return result
        }

        // Check expiration.
        if let exp = payload["exp"] as? TimeInterval {
            let expirationDate = Date(timeIntervalSince1970: exp)
            if expirationDate < Date() {
                return result // Token expired.
            }
            result.expiresAt = expirationDate
        }

        // Verify product ID and device identifier.
        if let license = payload["license"] as? [String: Any] {
            let tokenProductId = license["productId"] as? String
            if tokenProductId != KeyforgeConfig.productId {
                return result
            }
            result.email = license["email"] as? String
        }

        if let device = payload["device"] as? [String: Any] {
            let tokenDeviceId = device["identifier"] as? String
            if tokenDeviceId != deviceIdentifier {
                return result
            }
        }

        result.status = payload["status"] as? String ?? "active"
        result.isValid = (result.status == "active" || result.status == "fallbacked")

        return result
    }

    private func applyTokenClaims(_ result: TokenResult) {
        isLicensed = true
        licenseStatus = result.status
        licenseEmail = result.email
        licenseExpiresAt = result.expiresAt
    }

    // MARK: - Crypto Helpers

    /// Loads the ES256 (P-256) public key from the PEM string.
    private func loadES256PublicKey() -> P256.Signing.PublicKey? {
        let stripped = KeyforgeConfig.publicKeyPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        guard let derData = Data(base64Encoded: stripped) else { return nil }

        return try? P256.Signing.PublicKey(derRepresentation: derData)
    }

    /// Decodes a Base64URL-encoded string to Data.
    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to multiple of 4.
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(contentsOf: repeatElement("=", count: 4 - remainder))
        }

        return Data(base64Encoded: base64)
    }

    // MARK: - Networking

    private func postJSON(url: URL, body: [String: Any]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await URLSession.shared.data(for: request)
    }
}

// MARK: - Errors

enum LicenseError: LocalizedError {
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .serverError(let message):
            return message
        }
    }
}
