import SwiftUI
import UniformTypeIdentifiers

struct SidebandIdentityImporter: View {
    @State private var showFileImporter = false
    @State private var statusMessage = ""
    @State private var importedIdentityHash = ""

    var body: some View {
        VStack(spacing: 16) {
            Button {
                showFileImporter = true
            } label: {
                Label(
                    "Import Sideband Identity",
                    systemImage: "square.and.arrow.down"
                )
            }
            .buttonStyle(.borderedProminent)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        importedIdentityHash.isEmpty ? .red : .green
                    )
            }

            if !importedIdentityHash.isEmpty {
                Text(importedIdentityHash)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
    }

    private func handleImportResult(
        _ result: Result<[URL], Error>
    ) {
        do {
            let urls = try result.get()

            guard let selectedURL = urls.first else {
                statusMessage = "No identity file selected."
                importedIdentityHash = ""
                return
            }

            let didAccess =
                selectedURL.startAccessingSecurityScopedResource()

            defer {
                if didAccess {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }

            let privateKeyData = try Data(contentsOf: selectedURL)

            guard privateKeyData.count ==
                    ReticulumIdentity.combinedKeyByteCount else {
                statusMessage =
                    "Invalid identity file. Expected 64 bytes, but found \(privateKeyData.count)."

                importedIdentityHash = ""
                return
            }

            let identity =
                try ReticulumIdentityStore.shared.importIdentity(
                    from: privateKeyData
                )

            importedIdentityHash = identity.identityHashHex
            statusMessage = "Sideband identity imported successfully."

        } catch {
            statusMessage =
                "Identity import failed: \(error.localizedDescription)"

            importedIdentityHash = ""
        }
    }
}

#Preview {
    SidebandIdentityImporter()
}
