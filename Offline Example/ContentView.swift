//
//  ContentView.swift
//  Offline Example
//
//  Created by Nicholas Affonso on 21/03/26.
//

import SwiftUI

struct ContentView: View {
    @State private var licenseManager = LicenseManager()

    var body: some View {
        Group {
            if licenseManager.isCheckingLicense {
                ProgressView()
                    .frame(width: 440, height: 320)
            } else if licenseManager.isLicensed {
                SuccessView(licenseManager: licenseManager)
            } else {
                ActivationView(licenseManager: licenseManager)
            }
        }
        .task {
            await licenseManager.checkLicense()
        }
    }
}

#Preview {
    ContentView()
}
