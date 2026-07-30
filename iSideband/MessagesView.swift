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
    let lxmfMessageID: UUID?
    let lxmfHash: String?

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
        lxmfMessageID: UUID? = nil,
        lxmfHash: String? = nil,
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
        self.lxmfMessageID = lxmfMessageID
        self.lxmfHash = lxmfHash
        self.type = type
        self.attachmentName = attachmentName
        self.attachmentPath = attachmentPath
        self.attachmentSize = attachmentSize
    }
}

struct MessagesView: View {
    @ObservedObject var bluetooth: BluetoothManager
    let contact: LXMFContact?

    @EnvironmentObject
    private var lxmfManager: LXMFManager
    @ObservedObject private var incomingStore =
        LXMFIncomingMessageStore.shared

    @State private var messageText = ""
    @State private var messages: [ChatMessage]

    @State private var showingAttachmentMenu = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingVoiceMessageNotice = false
    @State private var showingAnnounceConfirmation = false
    @State private var announceButtonText = "Announce"
    @State private var isSendingAnnounce = false

    @State private var selectedPhoto: PhotosPickerItem?

    init(
        bluetooth: BluetoothManager,
        contact: LXMFContact? = nil
    ) {
        self.bluetooth = bluetooth
        self.contact = contact

        _messages = State(
            initialValue: Self.loadMessages(
                for: contact
            )
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
                        "Send an encrypted LXMF message to start this conversation."
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
        .toolbar {
            ToolbarItem(
                placement: .topBarTrailing
            ) {
                Button {
                    sendAnnounce()
                } label: {
                    Label(
                        announceButtonText,
                        systemImage:
                            isSendingAnnounce
                            ? "antenna.radiowaves.left.and.right"
                            : "dot.radiowaves.left.and.right"
                    )
                }
                .disabled(isSendingAnnounce)
                .accessibilityHint(
                    "Announce your iSideband identity"
                )
            }
        }
        .alert(
            "Announce",
            isPresented: $showingAnnounceConfirmation
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Announcement sent.")
        }
        .alert(
            "Voice Message",
            isPresented: $showingVoiceMessageNotice
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(
                """
                Voice messaging has been added to the attachment menu. Microphone recording and LXMF audio transfer will be connected in the next step.
                """
            )
        }
        .onAppear {
            lxmfManager.start(
                bluetooth: bluetooth
            )
            if let contact {
                incomingStore.markRead(
                    destinationHash:
                        contact.destinationHash
                )
            }
        }
        .onDisappear {
            if let contact {
                incomingStore.markRead(
                    destinationHash:
                        contact.destinationHash
                )
            }
        }
        .confirmationDialog(
            "Add Attachment",
            isPresented: $showingAttachmentMenu,
            titleVisibility: .visible
        ) {
            Button {
                showingPhotoPicker = true
            } label: {
                Label(
                    "Choose Photo",
                    systemImage: "photo"
                )
            }

            Button {
                showingFilePicker = true
            } label: {
                Label(
                    "Choose File",
                    systemImage: "doc"
                )
            }

            Button {
                showingVoiceMessageNotice = true
            } label: {
                Label(
                    "Record Voice Message",
                    systemImage: "mic.fill"
                )
            }

            Button("Take Photo — Coming Soon") { }
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
        .onChange(of: incomingStore.revision) {
            messages = Self.loadMessages(
                for: contact
            )
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

    private func sendAnnounce() {
        guard !isSendingAnnounce else {
            return
        }

        print("RETICULUM ANNOUNCE BUTTON PRESSED")

        isSendingAnnounce = true
        announceButtonText = "Sending…"

        lxmfManager.announceIdentity()

        Task {
            try? await Task.sleep(
                for: .milliseconds(500)
            )

            await MainActor.run {
                announceButtonText = "Announcement Sent"
                showingAnnounceConfirmation = true
            }

            try? await Task.sleep(
                for: .seconds(2)
            )

            await MainActor.run {
                announceButtonText = "Announce"
                isSendingAnnounce = false
            }
        }
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

        guard let peer = contact?.peer else {
            messages.append(
                ChatMessage(
                    text: trimmed,
                    isOutgoing: true,
                    status:
                        "Failed — select an LXMF contact"
                )
            )
            messageText = ""
            return
        }

        guard let queuedMessage = lxmfManager.send(
            text: trimmed,
            to: peer
        ) else {
            messages.append(
                ChatMessage(
                    text: trimmed,
                    isOutgoing: true,
                    status: "Failed"
                )
            )

            messageText = ""
            return
        }

        messages.append(
            ChatMessage(
                text: trimmed,
                date: nextConversationDate,
                isOutgoing: true,
                status: "Queued for LXMF",
                lxmfMessageID: queuedMessage.id
            )
        )

        messageText = ""
    }

    private var nextConversationDate: Date {
        guard let latest = messages.map(\.date).max() else {
            return Date()
        }
        return max(
            Date(),
            latest.addingTimeInterval(0.001)
        )
    }

    @ViewBuilder
    private func messageBubble(
        _ message: ChatMessage
    ) -> some View {
        MessageBubble(
            text: message.text,
            date: message.date,
            isOutgoing: message.isOutgoing,
            status: displayStatus(for: message),
            isPhoto: message.type == .photo,
            isFile: message.type == .file,
            attachmentName: message.attachmentName,
            attachmentPath: message.attachmentPath,
            attachmentSize: message.attachmentSize,
            onResend: canResend(message) ? {
                resend(message)
            } : nil
        )
    }

    private func canResend(
        _ message: ChatMessage
    ) -> Bool {
        guard message.isOutgoing,
              let id = message.lxmfMessageID else {
            return false
        }

        return lxmfManager.outgoingMessages.contains {
            $0.id == id && $0.status == .failed
        }
    }

    private func resend(
        _ message: ChatMessage
    ) {
        guard let id = message.lxmfMessageID,
              lxmfManager.resendMessage(id: id) else {
            return
        }
    }

    private func displayStatus(
        for message: ChatMessage
    ) -> String? {
        guard let lxmfMessageID = message.lxmfMessageID else {
            return message.status
        }

        guard let queuedMessage =
                lxmfManager.outgoingMessages.first(
                    where: {
                        $0.id == lxmfMessageID
                    }
                )
        else {
            return message.status
        }

        switch queuedMessage.status {
        case .queued:
            return "Queued"

        case .sending:
            return "Sending"

        case .sent:
            return "Sent"

        case .delivered:
            return "Delivered"

        case .failed:
            return "Failed"
        }
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
                let photoData = lxmfPhotoData(from: originalImage),
                let savedURL = savePhotoToDisk(photoData)
            else {
                await MainActor.run {
                    self.selectedPhoto = nil
                }

                return
            }

            await MainActor.run {
                guard let peer = contact?.peer,
                      let queued = lxmfManager.sendAttachment(
                        at: savedURL,
                        name: savedURL.lastPathComponent,
                        mimeType: "image/jpeg",
                        type: .photo,
                        to: peer
                      ) else {
                    messages.append(ChatMessage(
                        text: "", isOutgoing: true, status: "Failed",
                        type: .photo, attachmentName: savedURL.lastPathComponent,
                        attachmentPath: savedURL.path, attachmentSize: photoData.count
                    ))
                    self.selectedPhoto = nil
                    return
                }
                messages.append(
                    ChatMessage(
                        text: "",
                        isOutgoing: true,
                        status: "Sending",
                        lxmfMessageID: queued.id,
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

        guard let peer = contact?.peer,
              let queued = lxmfManager.sendAttachment(
                at: savedURL,
                name: sourceURL.lastPathComponent,
                mimeType: "application/octet-stream",
                type: .file,
                to: peer
              ) else {
            messages.append(ChatMessage(
                text: "", isOutgoing: true, status: "Failed", type: .file,
                attachmentName: sourceURL.lastPathComponent,
                attachmentPath: savedURL.path, attachmentSize: fileSize
            ))
            return
        }
        messages.append(
            ChatMessage(
                text: "",
                isOutgoing: true,
                status: "Sending",
                lxmfMessageID: queued.id,
                type: .file,
                attachmentName:
                    sourceURL.lastPathComponent,
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
           let image = UIImage(
                contentsOfFile: path
           ) {
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

        guard let documentsDirectory =
                fileManager.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                ).first
        else {
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

    private func lxmfPhotoData(from image: UIImage) -> Data? {
        var current = image
        for maximumDimension in [1280.0, 1024.0, 800.0, 640.0, 480.0] {
            let scale = min(
                1,
                maximumDimension / max(current.size.width, current.size.height)
            )
            if scale < 1 {
                let size = CGSize(
                    width: current.size.width * scale,
                    height: current.size.height * scale
                )
                current = UIGraphicsImageRenderer(size: size).image { _ in
                    current.draw(in: CGRect(origin: .zero, size: size))
                }
            }
            for quality in [0.75, 0.6, 0.45, 0.3] {
                if let data = current.jpegData(compressionQuality: quality),
                   data.count <= LXMFManager.maximumAttachmentBytes {
                    return data
                }
            }
        }
        return nil
    }

    private func saveFileToDisk(
        from sourceURL: URL
    ) -> URL? {
        let fileManager = FileManager.default

        guard let documentsDirectory =
                fileManager.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                ).first
        else {
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
                    """
                    \(UUID().uuidString)-\
                    \(sourceURL.lastPathComponent)
                    """
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

    private static let storageKeyPrefix =
        "savedDirectMessages"

    private static func storageKey(
        for contact: LXMFContact?
    ) -> String {
        guard let contact else {
            return storageKeyPrefix
        }

        return storageKeyPrefix +
            "." +
            contact.destinationHash
    }

    private static func loadMessages(
        for contact: LXMFContact?
    ) -> [ChatMessage] {
        let key = storageKey(
            for: contact
        )

        guard
            let data = UserDefaults.standard.data(
                forKey: key
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
            forKey: Self.storageKey(
                for: contact
            )
            )
    }
}

#Preview {
    NavigationStack {
        MessagesView(
            bluetooth: BluetoothManager()
        )
        .environmentObject(
            LXMFManager.shared
        )
    }
}
