import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

enum DirectMessageType: String, Codable, Hashable {
    case text
    case photo
    case file
}

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let date: Date
    let isOutgoing: Bool
    let status: String?

    let type: DirectMessageType
    let attachmentName: String?
    let attachmentPath: String?
    let attachmentSize: Int?

    init(
        id: UUID = UUID(),
        text: String,
        date: Date = Date(),
        isOutgoing: Bool,
        status: String? = nil,
        type: DirectMessageType = .text,
        attachmentName: String? = nil,
        attachmentPath: String? = nil,
        attachmentSize: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.isOutgoing = isOutgoing
        self.status = status
        self.type = type
        self.attachmentName = attachmentName
        self.attachmentPath = attachmentPath
        self.attachmentSize = attachmentSize
    }
}

struct MessagesView: View {
    @ObservedObject var bluetooth: BluetoothManager

    @State private var messageText = ""
    @State private var messages: [ChatMessage]

    @State private var showingAttachmentMenu = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth

        _messages = State(
            initialValue: Self.loadMessages()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "message")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)

                    Text("No Messages")
                        .font(.title2.bold())

                    Text(
                        "Messages sent here are currently raw radio-data tests."
                    )
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                }

                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { message in
                                messageBubble(message)
                                    .contextMenu {
                                        Button {
                                            copyMessage(message)
                                        } label: {
                                            Label(
                                                "Copy",
                                                systemImage: "doc.on.doc"
                                            )
                                        }

                                        Button(role: .destructive) {
                                            deleteMessage(message)
                                        } label: {
                                            Label(
                                                "Delete",
                                                systemImage: "trash"
                                            )
                                        }
                                    }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("BOTTOM")
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        withAnimation {
                            proxy.scrollTo(
                                "BOTTOM",
                                anchor: .bottom
                            )
                        }
                    }
                }
            }

            Divider()

            messageComposer
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Add Attachment",
            isPresented: $showingAttachmentMenu,
            titleVisibility: .visible
        ) {
            Button("Choose Photo") {
                showingPhotoPicker = true
            }

            Button("Choose File") {
                showingFilePicker = true
            }

            Button("Take Photo — Coming Soon") { }
                .disabled(true)

            Button("Voice Note — Coming Soon") { }
                .disabled(true)

            Button("Share Location — Coming Soon") { }
                .disabled(true)

            Button("Cancel", role: .cancel) { }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhoto,
            matching: .images
        )
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleSelectedFile(result)
        }
        .onChange(of: selectedPhoto) {
            handleSelectedPhoto()
        }
        .onChange(of: messages) {
            saveMessages()
        }
    }

    private var messageComposer: some View {
        MessageComposer(
            messageText: $messageText,
            onAttachmentTapped: {
                showingAttachmentMenu = true
            },
            onSendTapped: {
                sendMessage()
            }
        )
    }
    private var canSendMessage: Bool {
        !messageText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else {
            return
        }

        bluetooth.sendMessage(trimmed)

        messages.append(
            ChatMessage(
                text: trimmed,
                isOutgoing: true,
                status: "Sent to RNode"
            )
        )

        messageText = ""
    }
    @ViewBuilder
    private func messageBubble(
        _ message: ChatMessage
    ) -> some View {
        MessageBubble(
            text: message.text,
            date: message.date,
            isOutgoing: message.isOutgoing,
            status: message.status,
            isPhoto: message.type == .photo,
            isFile: message.type == .file,
            attachmentName: message.attachmentName,
            attachmentPath: message.attachmentPath,
            attachmentSize: message.attachmentSize
        )
    }

    private func handleSelectedPhoto() {
        guard let selectedPhoto else {
            return
        }

        Task {
            guard
                let originalData = try? await selectedPhoto
                    .loadTransferable(type: Data.self),
                let originalImage = UIImage(data: originalData),
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
                    ChatMessage(
                        text: "",
                        isOutgoing: true,
                        status: "Saved locally",
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

        guard let savedURL = saveFileToDisk(
            from: sourceURL
        ) else {
            return
        }

        let attributes = try? FileManager.default
            .attributesOfItem(
                atPath: savedURL.path
            )

        let fileSize = (
            attributes?[.size] as? NSNumber
        )?.intValue

        messages.append(
            ChatMessage(
                text: "",
                isOutgoing: true,
                status: "Saved locally",
                type: .file,
                attachmentName: sourceURL.lastPathComponent,
                attachmentPath: savedURL.path,
                attachmentSize: fileSize
            )
        )
    }

    private func copyMessage(
        _ message: ChatMessage
    ) {
        if message.type == .photo,
           let path = message.attachmentPath,
           let image = UIImage(contentsOfFile: path) {
            UIPasteboard.general.image = image
            return
        }

        if message.type == .file {
            UIPasteboard.general.string =
                message.attachmentName ?? "Attachment"
            return
        }

        UIPasteboard.general.string = message.text
    }

    private func deleteMessage(
        _ message: ChatMessage
    ) {
        if let attachmentPath = message.attachmentPath {
            try? FileManager.default.removeItem(
                atPath: attachmentPath
            )
        }

        messages.removeAll {
            $0.id == message.id
        }
    }

    private func savePhotoToDisk(
        _ data: Data
    ) -> URL? {
        let fileManager = FileManager.default

        guard let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let directory = documentsDirectory
            .appendingPathComponent(
                "DirectAttachments",
                isDirectory: true
            )

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let fileURL = directory
                .appendingPathComponent(
                    "\(UUID().uuidString).jpg"
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

        guard let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let directory = documentsDirectory
            .appendingPathComponent(
                "DirectAttachments",
                isDirectory: true
            )

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let destinationURL = directory
                .appendingPathComponent(
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

    private static let storageKey =
        "savedDirectMessages"

    private static func loadMessages() -> [ChatMessage] {
        guard
            let data = UserDefaults.standard.data(
                forKey: storageKey
            ),
            let savedMessages = try? JSONDecoder().decode(
                [ChatMessage].self,
                from: data
            )
        else {
            return []
        }

        return savedMessages
    }

    private func saveMessages() {
        guard let data = try? JSONEncoder().encode(
            messages
        ) else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: Self.storageKey
        )
    }
}

#Preview {
    NavigationStack {
        MessagesView(
            bluetooth: BluetoothManager()
        )
    }
}
