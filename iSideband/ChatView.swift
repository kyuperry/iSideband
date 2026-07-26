import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ChatView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject private var lxmfManager = LXMFManager.shared

    let title: String

    @State private var message = ""

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false
    @State private var isShowingCamera = false
    @State private var capturedImage: UIImage?

    @State private var messages: [Message] = [
        Message(
            text: "RNode connection established.",
            isMine: false
        ),
        Message(
            text: "Ready to send messages.",
            isMine: true
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            chatHeader

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(messages) { message in
                        messageBubble(
                            text: message.text,
                            isMine: message.isMine
                        )
                    }
                }
                .padding()
            }

            Divider()

            messageComposer
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(
            isPresented: $isShowingPhotoPicker,
            selection: $selectedPhoto,
            matching: .images
        )
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleSelectedFile(result)
        }
        .fullScreenCover(
            isPresented: $isShowingCamera
        ) {
            ChatCameraPicker(
                image: $capturedImage
            )
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) {
            handleSelectedPhoto()
        }
        .onChange(of: capturedImage) {
            handleCapturedImage()
        }
        .onAppear {
            lxmfManager.start(
                bluetooth: bluetooth
            )
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Text("Direct Message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(
            Color(uiColor: .systemBackground)
        )
    }

    private var messageComposer: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    isShowingPhotoPicker = true
                } label: {
                    Label(
                        "Photo Library",
                        systemImage: "photo"
                    )
                }

                Button {
                    isShowingCamera = true
                } label: {
                    Label(
                        "Take Photo",
                        systemImage: "camera"
                    )
                }

                Button {
                    isShowingFilePicker = true
                } label: {
                    Label(
                        "Choose File",
                        systemImage: "doc"
                    )
                }

                Button {
                    startVoiceMessage()
                } label: {
                    Label(
                        "Voice Message",
                        systemImage: "mic.fill"
                    )
                }
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(
                                Color.secondary.opacity(0.15)
                            )
                    )
            }
            .buttonStyle(.plain)

            TextField(
                "Message",
                text: $message,
                axis: .vertical
            )
            .lineLimit(1...5)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Color.secondary.opacity(0.12)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(
                                trimmedMessage.isEmpty
                                ? Color.gray.opacity(0.35)
                                : Color.accentColor
                            )
                            .animation(
                                .easeInOut(duration: 0.2),
                                value: message
                            )
                    )
            }
            .disabled(trimmedMessage.isEmpty)
        }
        .padding()
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func sendMessage() {
        guard !trimmedMessage.isEmpty else {
            return
        }

        let outgoingText = trimmedMessage

        let peer = LXMFPeer(
            displayName: title,
            destinationHash:
                "0123456789abcdef0123456789abcdef"
        )

        guard let queuedMessage = lxmfManager.send(
            text: outgoingText,
            to: peer
        ) else {
            print(
                "ChatView could not queue LXMF message"
            )
            return
        }

        _ = queuedMessage

        messages.append(
            Message(
                text: outgoingText,
                isMine: true
            )
        )

        message = ""
    }

    private func handleSelectedPhoto() {
        guard let selectedPhoto else {
            return
        }

        Task {
            guard
                let originalData = try? await selectedPhoto
                    .loadTransferable(type: Data.self),
                let originalImage = UIImage(
                    data: originalData
                ),
                let photoData = originalImage.jpegData(
                    compressionQuality: 0.8
                ),
                let savedURL = savePhotoToDisk(photoData)
            else {
                await MainActor.run {
                    self.selectedPhoto = nil
                }

                return
            }

            await MainActor.run {
                messages.append(
                    Message(
                        text: "",
                        isMine: true,
                        type: .photo,
                        attachmentName:
                            savedURL.lastPathComponent,
                        attachmentPath: savedURL.path,
                        attachmentSize: photoData.count
                    )
                )

                self.selectedPhoto = nil
            }
        }
    }

    private func handleCapturedImage() {
        guard
            let capturedImage,
            let photoData = capturedImage.jpegData(
                compressionQuality: 0.8
            ),
            let savedURL = savePhotoToDisk(photoData)
        else {
            return
        }

        messages.append(
            Message(
                text: "",
                isMine: true,
                type: .photo,
                attachmentName:
                    savedURL.lastPathComponent,
                attachmentPath: savedURL.path,
                attachmentSize: photoData.count
            )
        )

        self.capturedImage = nil
    }

    private func handleSelectedFile(
        _ result: Result<[URL], Error>
    ) {
        guard
            case .success(let urls) = result,
            let sourceURL = urls.first
        else {
            return
        }

        let hasAccess =
            sourceURL.startAccessingSecurityScopedResource()

        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard
            let savedURL = saveFileToDisk(
                from: sourceURL
            )
        else {
            return
        }

        let fileSize = try? FileManager.default
            .attributesOfItem(
                atPath: savedURL.path
            )[.size] as? Int

        messages.append(
            Message(
                text: "📎 \(savedURL.lastPathComponent)",
                isMine: true,
                type: .file,
                attachmentName: savedURL.lastPathComponent,
                attachmentPath: savedURL.path,
                attachmentSize: fileSize ?? nil
            )
        )
    }

    private func startVoiceMessage() {
        messages.append(
            Message(
                text: "🎙️ Voice message recording coming soon",
                isMine: true
            )
        )
    }

    private func savePhotoToDisk(
        _ data: Data
    ) -> URL? {
        let fileManager = FileManager.default

        guard
            let documentsDirectory =
                fileManager.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                ).first
        else {
            return nil
        }

        let attachmentsDirectory =
            documentsDirectory.appendingPathComponent(
                "DirectAttachments",
                isDirectory: true
            )

        do {
            try fileManager.createDirectory(
                at: attachmentsDirectory,
                withIntermediateDirectories: true
            )

            let filename =
                "\(UUID().uuidString).jpg"

            let fileURL =
                attachmentsDirectory.appendingPathComponent(
                    filename
                )

            try data.write(
                to: fileURL,
                options: .atomic
            )

            return fileURL
        } catch {
            print(
                "Could not save direct photo: \(error)"
            )

            return nil
        }
    }

    private func saveFileToDisk(
        from sourceURL: URL
    ) -> URL? {
        let fileManager = FileManager.default

        guard
            let documentsDirectory =
                fileManager.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                ).first
        else {
            return nil
        }

        let attachmentsDirectory =
            documentsDirectory.appendingPathComponent(
                "DirectAttachments",
                isDirectory: true
            )

        do {
            try fileManager.createDirectory(
                at: attachmentsDirectory,
                withIntermediateDirectories: true
            )

            let destinationURL =
                attachmentsDirectory.appendingPathComponent(
                    "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
                )

            try fileManager.copyItem(
                at: sourceURL,
                to: destinationURL
            )

            return destinationURL
        } catch {
            print(
                "Could not save direct file: \(error)"
            )

            return nil
        }
    }

    private func messageBubble(
        text: String,
        isMine: Bool
    ) -> some View {
        HStack {
            if isMine {
                Spacer()
            }

            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isMine
                    ? Color.accentColor
                    : Color.secondary.opacity(0.15)
                )
                .foregroundStyle(
                    isMine ? .white : .primary
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 18)
                )

            if !isMine {
                Spacer()
            }
        }
    }
}

private struct ChatCameraPicker:
    UIViewControllerRepresentable {

    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(
            image: $image,
            dismiss: dismiss
        )
    }

    func makeUIViewController(
        context: Context
    ) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator:
        NSObject,
        UINavigationControllerDelegate,
        UIImagePickerControllerDelegate {

        @Binding var image: UIImage?
        let dismiss: DismissAction

        init(
            image: Binding<UIImage?>,
            dismiss: DismissAction
        ) {
            _image = image
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info:
                [UIImagePickerController.InfoKey: Any]
        ) {
            image =
                info[.originalImage] as? UIImage

            dismiss()
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(
            bluetooth: BluetoothManager(),
            title: "Camp Node"
        )
    }
}
