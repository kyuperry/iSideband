import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import CryptoKit

enum DirectMessageType: String, Codable, Hashable {
    case text
    case photo
    case file
    case voiceNote
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
    @State private var showingVoiceRecorder = false
    @State private var showingAnnounceConfirmation = false
    @State private var announceButtonText = "Announce"
    @State private var isSendingAnnounce = false
    @FocusState private var isComposerFocused: Bool
    @State private var isViewingNewestMessage = true
    @State private var restoreKeyboardAtNewestMessage = false

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
                                        if let attachmentURL =
                                            saveableAttachmentURL(
                                                for: message
                                            ) {
                                            ShareLink(
                                                item: attachmentURL
                                            ) {
                                                Label(
                                                    message.type == .photo
                                                        ? "Save Photo…"
                                                        : "Save File…",
                                                    systemImage:
                                                        "square.and.arrow.down"
                                                )
                                            }
                                        }

                                        Button {
                                            copyMessage(message)
                                        } label: {
                                            Label(
                                                "Copy",
                                                systemImage: "doc.on.doc"
                                            )
                                        }

                                        if canResend(message) {
                                            Button {
                                                resend(message)
                                            } label: {
                                                Label(
                                                    "Retry",
                                                    systemImage:
                                                        "arrow.clockwise"
                                                )
                                            }
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
                    .scrollDismissesKeyboard(.immediately)
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        let distanceFromBottom =
                            geometry.contentSize.height
                            - geometry.containerSize.height
                            - geometry.contentOffset.y
                        return distanceFromBottom <= 24
                    } action: { _, isAtBottom in
                        guard isAtBottom != isViewingNewestMessage else {
                            return
                        }

                        isViewingNewestMessage = isAtBottom
                        if isAtBottom {
                            if restoreKeyboardAtNewestMessage {
                                isComposerFocused = true
                                restoreKeyboardAtNewestMessage = false
                            }
                        } else {
                            showingAttachmentMenu = false
                            restoreKeyboardAtNewestMessage =
                                isComposerFocused
                            isComposerFocused = false
                        }
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

            if showingAttachmentMenu {
                attachmentTray
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

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
        .sheet(isPresented: $showingVoiceRecorder) {
            VoiceNoteRecorderView { url in
                sendVoiceNote(at: url)
            }
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
        .onChange(of: selectedPhoto) { _, newPhoto in
            print(
                "PHOTO PICKER CHANGED: \(newPhoto != nil)"
            )

            guard newPhoto != nil else {
                return
            }

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
            isFocused: $isComposerFocused,
            onAttachmentTapped: {
                withAnimation(.snappy(duration: 0.22)) {
                    showingAttachmentMenu.toggle()
                }
            },
            onSendTapped: {
                sendMessage()
            }
        )
    }

    private var attachmentTray: some View {
        HStack(spacing: 12) {
            attachmentTrayButton(
                title: "Photo",
                systemImage: "photo.fill"
            ) {
                showingAttachmentMenu = false
                showingPhotoPicker = true
            }

            attachmentTrayButton(
                title: "File",
                systemImage: "doc.fill"
            ) {
                showingAttachmentMenu = false
                showingFilePicker = true
            }

            attachmentTrayButton(
                title: "Voice",
                systemImage: "mic.fill"
            ) {
                showingAttachmentMenu = false
                showingVoiceRecorder = true
            }

            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    showingAttachmentMenu = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close attachments")
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .background(.bar)
    }

    private func attachmentTrayButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Color.accentColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
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
        if isActivelyEstimating(message) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                messageBubbleContent(
                    message,
                    status: displayStatus(
                        for: message,
                        at: timeline.date
                    )
                )
            }
        } else {
            messageBubbleContent(
                message,
                status: displayStatus(for: message, at: Date())
            )
        }
    }

    private func messageBubbleContent(
        _ message: ChatMessage,
        status: String?
    ) -> some View {
        MessageBubble(
            text: message.text,
            date: message.date,
            isOutgoing: message.isOutgoing,
            status: status,
            isPhoto: message.type == .photo,
            isFile: message.type == .file,
            isVoiceNote: message.type == .voiceNote,
            attachmentName: message.attachmentName,
            attachmentPath: message.attachmentPath,
            attachmentSize: message.attachmentSize
        )
    }

    private func isActivelyEstimating(_ message: ChatMessage) -> Bool {
        guard let id = message.lxmfMessageID,
              let outgoing = lxmfManager.outgoingMessages.first(
                where: { $0.id == id }
              ),
              outgoing.attachment != nil else {
            return false
        }
        return outgoing.status == .queued || outgoing.status == .sending
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

    private func saveableAttachmentURL(
        for message: ChatMessage
    ) -> URL? {
        guard message.type == .photo || message.type == .file || message.type == .voiceNote,
              let path = message.attachmentPath else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
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
        for message: ChatMessage,
        at date: Date
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
            return transferStatus(
                prefix: "Queued",
                attachment: queuedMessage.attachment,
                startedAt: nil,
                now: date
            )

        case .sending:
            return transferStatus(
                prefix: "Sending",
                attachment: queuedMessage.attachment,
                startedAt: queuedMessage.transmissionStartedAt,
                now: date
            )

        case .sent:
            return "Sent"

        case .delivered:
            return "Delivered"

        case .failed:
            return "Failed"
        }
    }

    private func transferStatus(
        prefix: String,
        attachment: LXMFOutgoingAttachment?,
        startedAt: Date?,
        now: Date
    ) -> String {
        guard let attachment,
              let size = (try? FileManager.default.attributesOfItem(
                atPath: attachment.resolvedFileURL().path
              )[.size] as? NSNumber)?.intValue else {
            return prefix
        }
        let usableBitsPerSecond = max(
            Double(bluetooth.estimatedRadioBitrate) * 0.65,
            1
        )
        let totalSeconds = Int(ceil(Double(size * 8) / usableBitsPerSecond))
        let elapsed = startedAt.map {
            max(Int(now.timeIntervalSince($0)), 0)
        } ?? 0
        let seconds = totalSeconds - elapsed
        guard seconds > 0 else {
            return "\(prefix) • Finishing"
        }
        let estimate = seconds < 60
            ? "\(seconds)s"
            : "\(seconds / 60)m \(seconds % 60)s"
        return "\(prefix) • \(estimate)"
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
                guard let peer = contact?.peer else {
                    print("PHOTO SEND FAILED: contact peer is missing")

                    messages.append(
                        ChatMessage(
                            text: "",
                            isOutgoing: true,
                            status: "Failed",
                            type: .photo,
                            attachmentName: savedURL.lastPathComponent,
                            attachmentPath: savedURL.path,
                            attachmentSize: photoData.count
                        )
                    )

                    self.selectedPhoto = nil
                    return
                }

                print(
                    """
                    PHOTO SEND QUEUE ATTEMPT
                    Destination: \(peer.destinationHash)
                    Path: \(savedURL.path)
                    Exists: \(FileManager.default.fileExists(
                        atPath: savedURL.path
                    ))
                    Size: \(photoData.count) bytes
                    """
                )

                guard let queued = lxmfManager.sendAttachment(
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
                mimeType: UTType(
                    filenameExtension: sourceURL.pathExtension
                )?.preferredMIMEType ?? "application/octet-stream",
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

        if message.type == .file || message.type == .voiceNote {
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

            let digest = SHA256.hash(data: data)
                .prefix(10)
                .map { String(format: "%02x", $0) }
                .joined()
            let fileURL = directory
                .appendingPathComponent("photo-\(digest).jpg")

            if !fileManager.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL, options: .atomic)
            }

            return fileURL
        } catch {
            print(
                "Could not save direct photo: \(error)"
            )

            return nil
        }
    }

    private func lxmfPhotoData(from image: UIImage) -> Data? {
        let bitrate = Int(bluetooth.estimatedRadioBitrate)
        let targetPhotoBytes = bitrate < 2_500
            ? 12_000
            : (bitrate < 7_500 ? 20_000 : 40_000)
        var current = image
        for maximumDimension in [1280.0, 1024.0, 800.0, 640.0, 480.0, 360.0, 240.0] {
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
            for quality in [0.75, 0.6, 0.45, 0.3, 0.2, 0.15] {
                if let data = current.jpegData(compressionQuality: quality),
                   data.count <= targetPhotoBytes {
                    return data
                }
            }
        }
        return nil
    }

    private func sendVoiceNote(at url: URL) {
        let size = (try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.size] as? NSNumber)?.intValue
        guard let peer = contact?.peer,
              let queued = lxmfManager.sendAttachment(
                at: url,
                name: url.lastPathComponent,
                mimeType: "audio/ogg",
                type: .voiceNote,
                to: peer
              ) else {
            messages.append(ChatMessage(
                text: "", isOutgoing: true, status: "Failed",
                type: .voiceNote, attachmentName: url.lastPathComponent,
                attachmentPath: url.path, attachmentSize: size
            ))
            return
        }
        messages.append(ChatMessage(
            text: "", isOutgoing: true, status: "Sending",
            lxmfMessageID: queued.id, type: .voiceNote,
            attachmentName: url.lastPathComponent,
            attachmentPath: url.path, attachmentSize: size
        ))
    }

    private func saveFileToDisk(
        from sourceURL: URL
    ) -> URL? {
        let fileManager = FileManager.default

        guard let size = (try? fileManager.attributesOfItem(
            atPath: sourceURL.path
        )[.size] as? NSNumber)?.intValue,
              size > 0,
              size <= LXMFManager.maximumAttachmentBytes,
              let sourceData = try? Data(contentsOf: sourceURL) else {
            return nil
        }

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

            let digest = SHA256.hash(data: sourceData)
                .prefix(10)
                .map { String(format: "%02x", $0) }
                .joined()
            let destinationURL = directory.appendingPathComponent(
                "\(digest)-\(sourceURL.lastPathComponent)"
            )

            if !fileManager.fileExists(atPath: destinationURL.path) {
                try sourceData.write(to: destinationURL, options: .atomic)
            }

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
