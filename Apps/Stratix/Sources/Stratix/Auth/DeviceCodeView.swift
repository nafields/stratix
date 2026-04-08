// DeviceCodeView.swift
// Defines the device-code login screen, including QR rendering and manual code fallback.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import XCloudAPI

/// Shows the Microsoft device-code instructions while the app waits for browser authorization.
struct DeviceCodeView: View {
    let info: DeviceCodeInfo
    private let qrContext = CIContext()

    private var qrURLString: String {
        info.verificationUriComplete ?? info.verificationUri
    }

    private var manualURLString: String {
        info.verificationUri
    }

    /// Builds the QR and manual-code layout used during device-code sign-in.
    var body: some View {
        VStack(spacing: 34) {
            StratixWordmark(color: StratixTheme.Colors.focusTint)
                .scaleEffect(0.5)

            HStack(spacing: 56) {
                qrPanel
                codePanel
            }
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black, Color(red: 0.01, green: 0.05, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    private var qrPanel: some View {
        VStack(spacing: 20) {
            Text("Scan To Sign In")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Group {
                if let image = qrCodeImage(from: qrURLString) {
                    Image(decorative: image, scale: 1.0)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "qrcode")
                        .resizable()
                        .scaledToFit()
                        .padding(48)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: 380, maxHeight: 380)
            .padding(18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            Text("Use your phone camera to open the Microsoft sign-in page.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(32)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var codePanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(StratixTheme.Colors.focusTint)
                Text("Sign In To Xbox")
                    .font(.largeTitle.weight(.bold))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("If the QR code doesn't open, visit:")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(manualURLString)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Enter this code")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(info.userCode)
                    .font(.system(size: 64, weight: .heavy, design: .monospaced))
                    .foregroundStyle(StratixTheme.Colors.focusTint)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 18) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.35)
                Text("Waiting for authorization...")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// Renders a QR code image for the Microsoft verification URL.
    private func qrCodeImage(from string: String) -> CGImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }

        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return qrContext.createCGImage(scaled, from: scaled.extent)
    }
}

#if DEBUG
#Preview("Auth - Device Code", traits: .fixedLayout(width: 1920, height: 1080)) {
    DeviceCodeView(info: StratixPreviewFixtures.deviceCodeInfo)
}
#endif
