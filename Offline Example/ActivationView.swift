//
//  ActivationView.swift
//  Offline Example
//
//  License key entry and activation screen.
//

import SwiftUI

struct ActivationView: View {
    @State private var licenseKey = ""
    var licenseManager: LicenseManager

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("Activate Your License")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Enter your license key to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // License key input
            VStack(alignment: .leading, spacing: 6) {
                TextField("XXXXX-XXXXX-XXXXX-XXXXX-XXXXX", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 340)
                    .onSubmit {
                        activateIfValid()
                    }

                if let error = licenseManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Activate button
            Button(action: activateIfValid) {
                if licenseManager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 100)
                } else {
                    Text("Activate")
                        .frame(width: 100)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(licenseKey.isEmpty || licenseManager.isLoading)
        }
        .padding(40)
        .frame(width: 440, height: 320)
    }

    private func activateIfValid() {
        guard !licenseKey.isEmpty, !licenseManager.isLoading else { return }
        Task {
            await licenseManager.activate(licenseKey: licenseKey)
        }
    }
}
