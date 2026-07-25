import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct GroupChatView: View {
    let group: GroupConversation

    @State private var messages: [Message]
    @State private var draft = ""

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false

    init(group: GroupConversation) {
        self.group = group

        _messages = State(
            initialValue: Self.loadMessages(for: group.id)
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

                        messageBubble(for: message)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = message.text
                                } label: {
                                    Label(
                                        "Copy",
                                        systemImage: "doc.on.doc"
                                    )
                                }

                                Button(role: .destructive) {
                                    if let index = messages.firstIndex(of: message) {
                                        messages.remove(at: index)
                                    }
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

                Divider()

                messageComposer
            }
            .onAppear {
                scrollToLatestMessage(using: proxy)
            }
        }
        .navigationTitle(group.name)
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
        .onChange(of: selectedPhoto) {
            handleSelectedPhoto()
        }
    }

    private var messageComposer: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    isShowingPhotoPicker = true
                } label: {
                    Label(
                        "Choose Photo",
                        systemImage: "photo"
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
            } label: {
                Image(systemName: "plus")
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        Color.gray.opacity(0.15)
                    )
                    .clipShape(Circle())
            }

            TextField(
                "Type a message…",
                text: $draft,
                axis: .vertical
            )
            .lineLimit(1...5)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Color.gray.opacity(0.12)
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
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        canSendMessage
                            ? Color.accentColor
                            : Color.gray
                    )
                    .clipShape(Circle())
            }
            .disabled(!canSendMessage)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var canSendMessage: Bool {
        !draft.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    @ViewBuilder
    private func messageBubble(
        for message: Message
    ) -> some View {
        MessageBubble(
            text: message.text,
            date: Date(),
            isOutgoing: message.isMine,
            status: String(describing: message.status),
            isPhoto: message.type == .photo,
            isFile: message.type == .file,
            attachmentName: message.attachmentName,
            attachmentPath: message.attachmentPath,
            attachmentSize: message.attachmentSize
        )
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            return
        }

        messages.append(
            Message(
                text: text,
                isMine: true
            )
        )

        draft = ""

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1
        ) {
            messages.append(
                Message(
                    text: "Received: \(text)",
                    isMine: false
                )
            )
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
            print(
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
                forKey: storageKey(for: groupID)
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
        guard
            let data = try? JSONEncoder().encode(
                messages
            )
        else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: Self.storageKey(
                for: group.id
            )
        )
    }
}
