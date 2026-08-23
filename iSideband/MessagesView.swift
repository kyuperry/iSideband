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
    let sentAt: Date?
    let receivedAt: Date?
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
        sentAt: Date? = nil,
        receivedAt: Date? = nil,
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
        self.sentAt = sentAt
        self.receivedAt = receivedAt
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
    @Environment(\.nightVisionModeEnabled) private var isNightVisionEnabled
    @ObservedObject var bluetooth: BluetoothManager
    let contact: LXMFContact?

    @EnvironmentObject
    private var lxmfManager: LXMFManager
    @ObservedObject private var incomingStore =
        LXMFIncomingMessageStore.shared
    @AppStorage(PushToTalkPreferenceKey.enabled)
    private var pushToTalkEnabled = false

    @State private var messageText = ""
    @State private var messages: [ChatMessage]

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
    @State private var photoErrorMessage: String?
    @State private var isPreparingPhoto = false

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
                        .foregroundStyle(secondaryTextColor)

                    Text("No Messages")
                        .font(.title2.bold())

                    Text(
                        "Send an encrypted LXMF message to start this conversation."
                    )
                    .multilineTextAlignment(.center)
                    .foregroundStyle(secondaryTextColor)
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

            messageComposer
        }
        .navigationTitle(directChatTitle)
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
            VoiceNoteRecorderView(isPushToTalk: pushToTalkEnabled) { url in
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
            privacySafeLog(
                "PHOTO PICKER CHANGED: \(newPhoto != nil)"
            )

            guard newPhoto != nil else {
                return
            }

            handleSelectedPhoto()
        }
        .alert(
            "Photo Could Not Be Added",
            isPresented: Binding(
                get: { photoErrorMessage != nil },
                set: { if !$0 { photoErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { photoErrorMessage = nil }
        } message: {
            Text(photoErrorMessage ?? "")
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
            showsPushToTalk: pushToTalkEnabled,
            onPhotoTapped: {
                showingPhotoPicker = true
            },
            onFileTapped: {
                showingFilePicker = true
            },
            onVoiceTapped: {
                showingVoiceRecorder = true
            },
            onStatusTapped: { statusText in
                sendMessage(statusText)
            },
            onSendTapped: {
                sendMessage()
            }
        )
    }

    private var secondaryTextColor: Color {
        isNightVisionEnabled ? NightVisionPalette.secondary : .secondary
    }

    private var directChatTitle: String {
        guard let name = contact?.displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !name.isEmpty else {
            return "Messages"
        }
        return name
    }

    private func sendAnnounce() {
        guard !isSendingAnnounce else {
            return
        }

        privacySafeLog("RETICULUM ANNOUNCE BUTTON PRESSED")

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

    private func sendMessage(_ presetText: String? = nil) {
        let trimmed = (presetText ?? messageText).trimmingCharacters(
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
            if presetText == nil {
                messageText = ""
            }
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

            if presetText == nil {
                messageText = ""
            }
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

        if presetText == nil {
            messageText = ""
        }
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
        let outgoing = message.lxmfMessageID.flatMap { id in
            lxmfManager.outgoingMessages.first { $0.id == id }
        }
        return MessageBubble(
            text: message.text,
            date: message.date,
            sentAt: message.sentAt ?? outgoing?.sentAt,
            deliveredAt: outgoing?.deliveredAt,
            receivedAt: message.receivedAt,
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
        return outgoing.status == .queued || outgoing.status.isActiveTransfer
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

        case .waitingForInterface:
            return "Waiting for interface"

        case .retryScheduled:
            if let retryDate = queuedMessage.nextRetryAt {
                let seconds = max(
                    Int(ceil(retryDate.timeIntervalSince(date))),
                    1
                )
                return "Retrying in \(seconds)s"
            }
            return "Retry scheduled"

        case .sending:
            return transferStatus(
                prefix: "Sending",
                attachment: queuedMessage.attachment,
                startedAt: queuedMessage.transmissionStartedAt,
                now: date
            )

        case .waitingForPath:
            return "Finding route to peer"

        case .establishingLink:
            return "Establishing secure link"

        case .transferring:
            return transferStatus(
                prefix: "Transferring",
                attachment: queuedMessage.attachment,
                startedAt: queuedMessage.transmissionStartedAt,
                now: date
            )

        case .sent:
            return "Sent"

        case .delivered:
            return "Delivered"

        case .failed:
            if let reason = queuedMessage.lastError,
               !reason.isEmpty {
                return "Failed — \(reason)"
            }
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

        isPreparingPhoto = true
        Task {
            do {
                let photoData = try await PhotoAttachmentProcessor
                    .prepare(selectedPhoto)
                guard let savedURL = savePhotoToDisk(photoData) else {
                    throw PhotoAttachmentError.couldNotLoad
                }

                await MainActor.run {
                    queuePreparedPhoto(photoData, savedURL: savedURL)
                }
            } catch {
                await MainActor.run {
                    photoErrorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                self.selectedPhoto = nil
                isPreparingPhoto = false
            }
        }
    }

    private func queuePreparedPhoto(_ photoData: Data, savedURL: URL) {
        guard let peer = contact?.peer else {
            privacySafeLog("PHOTO SEND FAILED: contact peer is missing")
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
            return
        }

        privacySafeLog(
            """
            PHOTO SEND QUEUE ATTEMPT
            Destination: \(peer.destinationHash)
            Path: \(savedURL.path)
            Exists: \(FileManager.default.fileExists(atPath: savedURL.path))
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
            return
        }
        messages.append(
            ChatMessage(
                text: "",
                isOutgoing: true,
                status: "Sending",
                lxmfMessageID: queued.id,
                type: .photo,
                attachmentName: savedURL.lastPathComponent,
                attachmentPath: savedURL.path,
                attachmentSize: photoData.count
            )
        )
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
            privacySafeLog(
                "Could not save direct photo: \(error)"
            )

            return nil
        }
    }

    private func sendVoiceNote(at url: URL) {
        let size = (try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.size] as? NSNumber)?.intValue
        guard let size, size >= 64,
              let peer = contact?.peer,
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
            privacySafeLog(
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
        guard let contact else {
            let key = storageKey(for: nil)
            guard let data = UserDefaults.standard.data(forKey: key),
                  let messages = try? JSONDecoder().decode(
                    [ChatMessage].self,
                    from: data
                  ) else { return [] }
            return messages
        }

        let key = storageKey(for: contact)
        let databaseMessages = LXMFIncomingMessageStore.shared.messages(
            for: contact.destinationHash
        )
        let legacyMessages = UserDefaults.standard.data(forKey: key)
            .flatMap {
                try? JSONDecoder().decode([ChatMessage].self, from: $0)
            } ?? []
        var merged: [String: ChatMessage] = [:]
        for message in databaseMessages + legacyMessages {
            let identity = message.lxmfHash ??
                message.lxmfMessageID?.uuidString ??
                message.id.uuidString
            merged[identity] = message
        }
        let messages = merged.values.sorted { $0.date < $1.date }
        if !legacyMessages.isEmpty,
           LXMFIncomingMessageStore.shared.replaceMessages(
            messages,
            for: contact.destinationHash
           ) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return messages
    }

    private func saveMessages() {
        guard let contact else {
            guard let data = try? JSONEncoder().encode(messages) else {
                return
            }
            UserDefaults.standard.set(
                data,
                forKey: Self.storageKey(for: nil)
            )
            return
        }
        _ = LXMFIncomingMessageStore.shared.replaceMessages(
            messages,
            for: contact.destinationHash
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
