//
//  SuccessView.swift
//  Offline Example
//
//  Shown when the user has a valid, activated license.
//

import SwiftUI

struct SuccessView: View {
    var licenseManager: LicenseManager

    private var isFallbacked: Bool {
        licenseManager.licenseStatus == "fallbacked"
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: isFallbacked ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(isFallbacked ? .orange : .green)

                Text(isFallbacked ? "Limited Access" : "License Active")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(isFallbacked
                     ? "Your license has expired, but perpetual access is still granted."
                     : "Your app is licensed and ready to use.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // License details
            VStack(spacing: 10) {
                LicenseDetailRow(label: "Status", value: licenseManager.licenseStatus.capitalized)

                if let email = licenseManager.licenseEmail {
                    LicenseDetailRow(label: "Email", value: email)
                }

                if let expires = licenseManager.licenseExpiresAt {
                    LicenseDetailRow(
                        label: "Token Expires",
                        value: expires.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }
            .padding()
            .background(.fill.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Actions
            HStack(spacing: 12) {
                Button("Refresh Token") {
                    Task {
                        await licenseManager.refreshToken()
                    }
                }

                Button("Deactivate") {
                    licenseManager.deactivate()
                }
                .foregroundStyle(.red)
            }
        }
        .padding(40)
        .frame(width: 440, height: 320)
    }
}

private struct LicenseDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}
