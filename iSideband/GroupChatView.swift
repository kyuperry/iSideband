import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct GroupChatView: View {
    @Environment(\.nightVisionModeEnabled) private var isNightVisionEnabled
    @ObservedObject var bluetooth: BluetoothManager
    let group: GroupConversation
    @ObservedObject private var lxmfManager = LXMFManager.shared
    @ObservedObject private var groupStore = GroupMessageStore.shared

    @State private var messages: [Message]
    @State private var draft = ""

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoErrorMessage: String?
    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false
    @State private var isShowingCamera = false
    @State private var capturedImage: UIImage?
    @State private var showingVoiceRecorder = false
    @State private var isShowingAttachmentPicker = false
    @State private var sendErrorMessage: String?
    @State private var showingAnnounceConfirmation = false
    @State private var announceButtonText = "Announce"
    @State private var isSendingAnnounce = false
    @State private var hasScrollableMessageContent = false
    @State private var isViewingNewestMessage = true

    init(bluetooth: BluetoothManager, group: GroupConversation) {
        self.bluetooth = bluetooth
        self.group = group

        _messages = State(
            initialValue: Self.loadMessages(
                for: group.id
            )
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                List(messages) { message in
                    HStack {
                        if message.isMine {
                            Spacer()
                        }

                        groupMessageContent(for: message)
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
                                    UIPasteboard.general.string =
                                        message.text
                                } label: {
                                    Label(
                                        "Copy",
                                        systemImage: "doc.on.doc"
                                    )
                                }

                                if canRetry(message) {
                                    Button {
                                        retry(message)
                                    } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
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

                        if !message.isMine {
                            Spacer()
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .id(message.id)
                }
                .listStyle(.plain)
                .onChange(of: messages) {
                    saveMessages()
                    scrollToLatestMessage(using: proxy)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height >
                        geometry.containerSize.height + 1
                } action: { _, isScrollable in
                    hasScrollableMessageContent = isScrollable
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.visibleRect.maxY >=
                        geometry.contentSize.height - 24
                } action: { _, isAtBottom in
                    isViewingNewestMessage = isAtBottom
                }
                .overlay(alignment: .bottomLeading) {
                    if hasScrollableMessageContent &&
                        !isViewingNewestMessage {
                        Button {
                            scrollToLatestMessage(using: proxy)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(
                                    .system(
                                        size: 17,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(Color.blue)
                                .frame(width: 34, height: 34)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Jump to latest message"
                        )
                        .padding(.leading, 8)
                        .padding(.bottom, 8)
                    }
                }

                Divider()

                messageComposer
            }
            .onAppear {
                scrollToLatestMessage(using: proxy)
            }
        }
        .navigationTitle(groupChatTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { sendAnnounce() } label: {
                    Label(
                        announceButtonText,
                        systemImage: isSendingAnnounce
                            ? "antenna.radiowaves.left.and.right"
                            : "dot.radiowaves.left.and.right"
                    )
                }
                .disabled(isSendingAnnounce)
                .accessibilityHint("Announce your iSideband identity")
            }
        }
        .alert("Announce", isPresented: $showingAnnounceConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Announcement sent.")
        }
        .onAppear {
            lxmfManager.start(bluetooth: bluetooth)
        }
        .photosPicker(
            isPresented: $isShowingPhotoPicker,
            selection: $selectedPhoto,
            matching: .images
        )
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
            GroupCameraPicker(
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
        .sheet(isPresented: $showingVoiceRecorder) {
            VoiceNoteRecorderView { url in
                sendVoiceNote(at: url)
            }
        }
        .alert("Group Message Could Not Be Sent", isPresented: Binding(
            get: { sendErrorMessage != nil },
            set: { if !$0 { sendErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { sendErrorMessage = nil }
        } message: {
            Text(sendErrorMessage ?? "")
        }
        .onChange(of: groupStore.revision) {
            messages = groupStore.messages(for: group.id)
        }
    }

    private var groupChatTitle: String {
        let name = group.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return name.isEmpty ? "Group Chat" : name
    }

    private func sendAnnounce() {
        guard !isSendingAnnounce else { return }
        privacySafeLog("RETICULUM GROUP CHAT ANNOUNCE BUTTON PRESSED")
        isSendingAnnounce = true
        announceButtonText = "Sending…"
        lxmfManager.announceIdentity()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                announceButtonText = "Announcement Sent"
                showingAnnounceConfirmation = true
            }
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                announceButtonText = "Announce"
                isSendingAnnounce = false
            }
        }
    }

    private var messageComposer: some View {
        HStack(spacing: 10) {
            Button {
                isShowingAttachmentPicker = true
            } label: {
                Image(systemName: "plus")
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        isNightVisionEnabled
                            ? NightVisionPalette.primary
                            : .primary
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(
                                isNightVisionEnabled
                                    ? NightVisionPalette.surface
                                    : Color.secondary.opacity(0.15)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add attachment")
            .popover(isPresented: $isShowingAttachmentPicker) {
                groupAttachmentPicker
                    .presentationCompactAdaptation(.popover)
            }

            TextField(
                "Type a message…",
                text: $draft,
                axis: .vertical
            )
            .lineLimit(1...5)
            .foregroundStyle(
                isNightVisionEnabled
                    ? NightVisionPalette.primary
                    : Color.primary
            )
            .tint(
                isNightVisionEnabled
                    ? NightVisionPalette.primary
                    : Color.accentColor
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isNightVisionEnabled
                    ? NightVisionPalette.field
                    : Color.secondary.opacity(0.12)
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
                    .font(
                        .system(
                            size: 17,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        isNightVisionEnabled
                            ? NightVisionPalette.primary
                            : .white
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(
                                isNightVisionEnabled
                                    ? (canSendMessage
                                        ? NightVisionPalette.strongSurface
                                        : NightVisionPalette.disabled)
                                    : (canSendMessage
                                        ? Color.accentColor
                                        : Color.gray.opacity(0.4))
                            )
                    )
            }
            .disabled(!canSendMessage)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var groupAttachmentPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupAttachmentButton("Photo Library", systemImage: "photo") {
                isShowingPhotoPicker = true
            }
            groupAttachmentButton("Take Photo", systemImage: "camera") {
                isShowingCamera = true
            }
            groupAttachmentButton("Choose File", systemImage: "doc") {
                isShowingFilePicker = true
            }
            Menu {
                ForEach(groupStatusMessages, id: \.self) { status in
                    Button(status) { sendText(status) }
                }
            } label: {
                Label("Status", systemImage: "exclamationmark.bubble")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            groupAttachmentButton("Voice Message", systemImage: "mic.fill") {
                showingVoiceRecorder = true
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 200)
        .background(
            isNightVisionEnabled
                ? NightVisionPalette.field
                : Color(.systemBackground)
        )
    }

    private func groupAttachmentButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            isShowingAttachmentPicker = false
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isNightVisionEnabled
                ? NightVisionPalette.primary
                : Color.primary
        )
    }

    private var canSendMessage: Bool {
        !draft.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private func saveableAttachmentURL(
        for message: Message
    ) -> URL? {
        guard message.type == .photo || message.type == .file ||
                message.type == .voiceNote,
              let path = message.attachmentPath else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    @ViewBuilder
    private func groupMessageContent(
        for message: Message
    ) -> some View {
        VStack(
            alignment: message.isMine ? .trailing : .leading,
            spacing: 3
        ) {
            if !message.isMine {
                Text(senderLabel(for: message))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        isNightVisionEnabled
                            ? NightVisionPalette.secondary
                            : Color.accentColor
                    )
                    .padding(.leading, 12)
            }

            MessageBubble(
                text: message.text,
                date: message.createdAt,
                sentAt: sentDate(for: message),
                deliveredAt: deliveredDate(for: message),
                receivedAt: message.receivedAt,
                isOutgoing: message.isMine,
                status: statusText(for: message),
                isPhoto: message.type == .photo,
                isFile: message.type == .file,
                isVoiceNote: message.type == .voiceNote,
                attachmentName: message.attachmentName,
                attachmentPath: message.attachmentPath,
                attachmentSize: message.attachmentSize
            )
        }
    }

    private func senderLabel(for message: Message) -> String {
        if let name = message.senderDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        if let destination = message.senderDestinationHash?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !destination.isEmpty {
            if let contact = LXMFContactStore.shared.contact(
                for: destination
            ) {
                return contact.displayName
            }
            return "RNode \(destination.prefix(8))"
        }

        return "Unknown RNode"
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            return
        }

        if sendText(text) { draft = "" }
    }

    @discardableResult
    private func sendText(_ text: String) -> Bool {
        let logicalID = UUID()
        guard let encoded = makeEnvelope(id: logicalID, body: text)?.encoded() else {
            sendErrorMessage = "This group does not have any valid members."
            return false
        }
        let outgoing = groupPeers.compactMap { lxmfManager.send(text: encoded, to: $0) }
        guard outgoing.count == groupPeers.count, !outgoing.isEmpty else {
            sendErrorMessage = "One or more group members could not be queued."
            return false
        }
        messages.append(Message(id: logicalID, text: text, isMine: true,
                                status: .queued, outgoingMessageIDs: outgoing.map(\.id)))
        saveMessages()
        return true
    }

    private func deleteMessage(
        _ message: Message
    ) {
        guard
            let index = messages.firstIndex(
                of: message
            )
        else {
            return
        }

        messages.remove(at: index)
    }

    private func handleSelectedPhoto() {
        guard let selectedPhoto else {
            return
        }

        Task {
            do {
                let photoData = try await PhotoAttachmentProcessor
                    .prepare(selectedPhoto)
                guard let savedURL = savePhotoToDisk(photoData) else {
                    throw PhotoAttachmentError.couldNotLoad
                }
                await MainActor.run {
                    appendPhotoMessage(url: savedURL, size: photoData.count)
                    self.selectedPhoto = nil
                }
            } catch {
                await MainActor.run {
                    photoErrorMessage = error.localizedDescription
                    self.selectedPhoto = nil
                }
            }
        }
    }

    private func handleCapturedImage() {
        guard
            let capturedImage,
            let photoData = PhotoAttachmentProcessor.jpegData(
                from: capturedImage
            ),
            let savedURL = savePhotoToDisk(
                photoData
            )
        else {
            return
        }

        appendPhotoMessage(
            url: savedURL,
            size: photoData.count
        )

        self.capturedImage = nil
    }

    private func appendPhotoMessage(
        url: URL,
        size: Int
    ) {
        sendAttachment(url: url, type: .photo, messageType: .photo, size: size)
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
            sourceURL
                .startAccessingSecurityScopedResource()

        defer {
            if hasAccess {
                sourceURL
                    .stopAccessingSecurityScopedResource()
            }
        }

        guard
            let savedURL = saveFileToDisk(
                from: sourceURL
            )
        else {
            return
        }

        let attributes =
            try? FileManager.default
                .attributesOfItem(
                    atPath: savedURL.path
                )

        let fileSize =
            attributes?[.size] as? Int

        sendAttachment(url: savedURL, type: .file, messageType: .file, size: fileSize)
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
                "GroupAttachments",
                isDirectory: true
            )

        do {
            try fileManager.createDirectory(
                at: attachmentsDirectory,
                withIntermediateDirectories: true
            )

            let fileURL =
                attachmentsDirectory.appendingPathComponent(
                    "\(UUID().uuidString).jpg"
                )

            try data.write(
                to: fileURL,
                options: .atomic
            )

            return fileURL
        } catch {
            privacySafeLog(
                "Could not save group photo: \(error)"
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
                "GroupAttachments",
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
            privacySafeLog(
                "Could not save group file: \(error)"
            )

            return nil
        }
    }

    private func scrollToLatestMessage(
        using proxy: ScrollViewProxy
    ) {
        guard let lastMessage = messages.last else {
            return
        }

        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(
                    lastMessage.id,
                    anchor: .bottom
                )
            }
        }
    }

    private static func storageKey(
        for groupID: UUID
    ) -> String {
        "groupMessages-\(groupID.uuidString)"
    }

    private static func loadMessages(
        for groupID: UUID
    ) -> [Message] {
        guard
            let data = UserDefaults.standard.data(
                forKey: storageKey(
                    for: groupID
                )
            ),
            let savedMessages =
                try? JSONDecoder().decode(
                    [Message].self,
                    from: data
                )
        else {
            return []
        }

        return savedMessages
    }

    private func saveMessages() {
        groupStore.save(messages, for: group.id)
    }

    private var groupStatusMessages: [String] {
        ["Status Check", "In Contact", "Regroup on me", "Emergency"]
    }

    private var groupPeers: [LXMFPeer] {
        let localHash = ReticulumCoreBridge.shared.destinationHash.lowercased()
        return Array(Set(group.memberDestinationHashes ?? []))
            .filter { $0.lowercased() != localHash }
            .prefix(8).compactMap { hash in
            if let contact = LXMFContactStore.shared.contact(for: hash) { return contact.peer }
            let peer = LXMFPeer(displayName: "RNode \(hash.prefix(8))", destinationHash: hash)
            return peer.isDestinationValid ? peer : nil
        }
    }

    private func makeEnvelope(id: UUID, body: String) -> GroupWireEnvelope? {
        let members = groupPeers.map(\.destinationHash)
        guard !members.isEmpty else { return nil }
        let localHash = ReticulumCoreBridge.shared.destinationHash.lowercased()
        let participants = localHash.count == 32
            ? Array(Set(members + [localHash]))
            : members
        return GroupWireEnvelope(groupID: group.id, groupName: group.name,
            groupSystemImage: group.systemImage, memberDestinationHashes: participants,
            logicalMessageID: id, body: body)
    }

    private func sendAttachment(url: URL, type: LXMFOutgoingAttachmentType,
                                messageType: MessageType, size: Int?) {
        let logicalID = UUID()
        let body = messageType == .file ? "📎 \(url.lastPathComponent)" : ""
        guard let encoded = makeEnvelope(id: logicalID, body: body)?.encoded() else {
            sendErrorMessage = "This group does not have any valid members."
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        let outgoing = groupPeers.compactMap {
            lxmfManager.sendAttachment(at: url, name: url.lastPathComponent,
                mimeType: mime, type: type, caption: encoded, to: $0)
        }
        guard outgoing.count == groupPeers.count, !outgoing.isEmpty else {
            sendErrorMessage = "One or more group attachments could not be queued."
            return
        }
        messages.append(Message(id: logicalID, text: body, isMine: true,
            type: messageType, attachmentName: url.lastPathComponent,
            attachmentPath: url.path, attachmentSize: size, status: .queued,
            outgoingMessageIDs: outgoing.map(\.id)))
        saveMessages()
    }

    private func sendVoiceNote(at url: URL) {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size]
            as? NSNumber)?.intValue
        guard let size, size >= 64 else {
            sendErrorMessage = "The voice recording was empty."
            return
        }
        sendAttachment(url: url, type: .voiceNote, messageType: .voiceNote, size: size)
    }

    private func canRetry(_ message: Message) -> Bool {
        outgoing(for: message).contains { $0.status == .failed }
    }

    private func retry(_ message: Message) {
        let failed = outgoing(for: message).filter { $0.status == .failed }
        guard failed.contains(where: { lxmfManager.resendMessage(id: $0.id) }) else {
            sendErrorMessage = "The message could not be retried. Its attachment may no longer be available."
            return
        }
    }

    private func outgoing(for message: Message) -> [LXMFOutgoingMessage] {
        let ids = Set(message.outgoingMessageIDs)
        return lxmfManager.outgoingMessages.filter { ids.contains($0.id) }
    }

    private func deliveredDate(for message: Message) -> Date? {
        let attempts = outgoing(for: message)
        guard !attempts.isEmpty, attempts.allSatisfy({ $0.status == .delivered }) else {
            return message.deliveredAt
        }
        return attempts.compactMap(\.deliveredAt).max()
    }

    private func sentDate(for message: Message) -> Date? {
        let attempts = outgoing(for: message)
        guard !attempts.isEmpty,
              attempts.allSatisfy({ $0.sentAt != nil }) else {
            return nil
        }
        // A group message is fully sent when its final per-member copy is sent.
        return attempts.compactMap(\.sentAt).max()
    }

    private func statusText(for message: Message) -> String? {
        guard message.isMine else { return "Received" }
        let attempts = outgoing(for: message)
        guard !attempts.isEmpty else { return message.status.rawValue.capitalized }
        let delivered = attempts.filter { $0.status == .delivered }.count
        let sent = attempts.filter {
            $0.status == .sent || $0.status == .delivered
        }.count
        if delivered == attempts.count { return "Delivered" }
        if attempts.allSatisfy({ $0.status == .failed }) { return "Failed" }
        if delivered > 0 { return "Delivered \(delivered)/\(attempts.count)" }
        if attempts.contains(where: { $0.status == .retryScheduled }) { return "Retry scheduled" }
        if attempts.contains(where: { $0.status == .waitingForInterface }) {
            return "Waiting for interface"
        }
        if attempts.contains(where: { $0.status == .waitingForPath }) {
            return "Waiting for path"
        }
        if attempts.contains(where: { $0.status == .establishingLink }) {
            return "Establishing link"
        }
        if attempts.contains(where: { $0.status == .transferring }) { return "Sending" }
        if attempts.contains(where: { $0.status.isActiveTransfer }) { return "Sending" }
        if sent == attempts.count { return "Sent" }
        if sent > 0 { return "Sent \(sent)/\(attempts.count)" }
        if attempts.contains(where: { $0.status == .failed }) { return "Failed (some members)" }
        return "Queued"
    }
}

private struct GroupCameraPicker:
    UIViewControllerRepresentable {

    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(
        context: Context
    ) -> UIImagePickerController {
        let picker = UIImagePickerController()

        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false

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

        let parent: GroupCameraPicker

        init(parent: GroupCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info:
                [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image =
                info[.originalImage] as? UIImage

            parent.dismiss()
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            parent.dismiss()
        }
    }
}
