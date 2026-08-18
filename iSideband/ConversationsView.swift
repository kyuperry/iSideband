import SwiftUI

private struct ScannedLXMFPeer: Identifiable {
    let id = UUID()
    let displayName: String
    let destinationHash: String
}

struct ConversationsView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject private var contactStore =
        LXMFContactStore.shared
    @ObservedObject private var messageStore =
        LXMFIncomingMessageStore.shared
    @State private var selectedTab: ConversationTab = .direct
    @State private var showCreateGroup = false
    @State private var showAddLXMFContact = false
    @State private var showingAnnounceMessage = false
    @State private var contactPendingDeletion: LXMFContact?
    @State private var contactPendingEdit: LXMFContact?
    @State private var groupPendingDeletion: GroupConversation?
    @State private var showQRScanner = false
    @State private var qrScanMessage: String?
    @State private var scannedPeer: ScannedLXMFPeer?

    @State private var groupName = ""
    @State private var selectedGroupIcon = "person.3.fill"

    @State private var groups: [GroupConversation] =
        Self.loadGroups()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .direct:
                    directConversations

                case .groups:
                    groupConversations
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            conversationTabBar
        }
        .overlay(alignment: .bottomTrailing) {
            floatingAddButton
                .padding(.trailing, 20)
                .padding(.bottom, 92)
        }
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(
                placement: .topBarTrailing
            ) {
                Button {
                    announceIdentity()
                } label: {
                    Image(
                        systemName:
                            "dot.radiowaves.left.and.right"
                    )
                }
                .accessibilityLabel("Announce")
            }
        }
        .alert(
            "Announce",
            isPresented: $showingAnnounceMessage
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Announcement sent.")
        }
        .confirmationDialog(
            "Delete Direct Chat?",
            isPresented: Binding(
                get: { contactPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        contactPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(
                "Delete Chat",
                role: .destructive
            ) {
                if let contact = contactPendingDeletion {
                    deleteDirectConversation(contact)
                }
            }
            Button("Cancel", role: .cancel) {
                contactPendingDeletion = nil
            }
        } message: {
            Text(
                "This removes the contact and all saved messages in this conversation."
            )
        }
        .confirmationDialog(
            "Delete Group?",
            isPresented: Binding(
                get: { groupPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        groupPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(
                "Delete Group",
                role: .destructive
            ) {
                if let group = groupPendingDeletion {
                    deleteGroupConversation(group)
                }
            }
            Button("Cancel", role: .cancel) {
                groupPendingDeletion = nil
            }
        } message: {
            Text(
                "This removes the group and all of its saved messages."
            )
        }
        .sheet(
            isPresented: $showCreateGroup
        ) {
            createGroupSheet
        }
        .navigationDestination(
            isPresented: $showAddLXMFContact
        ) {
            AddLXMFContactView { contact in
                do {
                    try LXMFContactStore.shared.add(
                        contact
                    )

                    print(
                        """
                        SAVED LXMF CONTACT
                        Name: \(contact.displayName)
                        Destination: \(contact.destinationHash)
                        """
                    )

                    showAddLXMFContact = false
                } catch {
                    print(
                        "Failed to save LXMF contact: " +
                        error.localizedDescription
                    )
                }
            }
        }
        .sheet(item: $contactPendingEdit) { contact in
            AddLXMFContactView(
                contact: contact
            ) { updatedContact in
                do {
                    try contactStore.update(
                        updatedContact
                    )
                } catch {
                    print(
                        "Failed to update LXMF contact: " +
                        error.localizedDescription
                    )
                }
            }
        }
        .fullScreenCover(isPresented: $showQRScanner) {
            LXMFQRCodeScannerView { result in
                showQRScanner = false
                switch result {
                case .success(let value):
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        handleScannedQRCode(value)
                    }
                case .failure(let error):
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        qrScanMessage = error.localizedDescription
                    }
                }
            }
        }
        .alert(
            "QR Code",
            isPresented: Binding(
                get: { qrScanMessage != nil },
                set: { if !$0 { qrScanMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { qrScanMessage = nil }
        } message: {
            Text(qrScanMessage ?? "")
        }
        .sheet(item: $scannedPeer) { peer in
            AddLXMFContactView(
                initialDisplayName: peer.displayName,
                initialDestinationHash: peer.destinationHash
            ) { contact in
                do {
                    try contactStore.add(contact)
                    qrScanMessage = "Peer added to your contacts."
                } catch {
                    qrScanMessage = error.localizedDescription
                }
                scannedPeer = nil
            }
        }
    }

    private func handleScannedQRCode(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if value.lowercased().hasPrefix("lxm://") {
            qrScanMessage = ReticulumCoreBridge.shared
                .ingestPaperMessageURI(value)
            return
        }

        if let peer = Self.decodePeerQRCode(value) {
            if contactStore.contains(destinationHash: peer.destinationHash) {
                qrScanMessage = "That peer is already in your contacts."
            } else {
                scannedPeer = peer
            }
            return
        }

        qrScanMessage =
            "The QR code is not a valid LXMF paper message or 32-character peer destination."
    }

    private static func decodePeerQRCode(
        _ value: String
    ) -> ScannedLXMFPeer? {
        if let data = value.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] {
            let hash = object["destination_hash"] as? String
                ?? object["destinationHash"] as? String
                ?? object["lxmf_address"] as? String
            if let hash, let cleaned = validDestinationHash(hash) {
                let name = object["display_name"] as? String
                    ?? object["displayName"] as? String
                    ?? object["name"] as? String
                    ?? ""
                return ScannedLXMFPeer(
                    displayName: name,
                    destinationHash: cleaned
                )
            }
        }

        if let components = URLComponents(string: value) {
            let queryHash = components.queryItems?.first {
                ["destination", "destination_hash", "hash", "address"]
                    .contains($0.name.lowercased())
            }?.value
            let pathCandidate = components.host ??
                components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let cleaned = validDestinationHash(queryHash ?? pathCandidate) {
                let name = components.queryItems?.first {
                    ["name", "display_name"].contains($0.name.lowercased())
                }?.value ?? ""
                return ScannedLXMFPeer(
                    displayName: name,
                    destinationHash: cleaned
                )
            }
        }

        guard let cleaned = validDestinationHash(value) else {
            return nil
        }
        return ScannedLXMFPeer(
            displayName: "",
            destinationHash: cleaned
        )
    }

    private static func validDestinationHash(
        _ candidate: String
    ) -> String? {
        let cleaned = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard cleaned.count == 32,
              cleaned.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return cleaned
    }

    private var floatingAddButton: some View {
        Menu {
            NavigationLink {
                LXMFContactPickerView(
                    bluetooth: bluetooth
                )
            } label: {
                Label(
                    "Start Direct Chat",
                    systemImage: "person.fill"
                )
            }

            Button {
                showCreateGroup = true
            } label: {
                Label(
                    "Create Group",
                    systemImage: "person.3.fill"
                )
            }

            NavigationLink {
                DiscoveredPeersView()
            } label: {
                Label(
                    "Discovered Peers",
                    systemImage:
                        "antenna.radiowaves.left.and.right"
                )
            }

            Button {
                showAddLXMFContact = true
            } label: {
                Label(
                    "Add LXMF Contact",
                    systemImage:
                        "person.crop.circle.badge.plus"
                )
            }

            Button {
                showQRScanner = true
            } label: {
                Label(
                    "Scan QR Code",
                    systemImage: "qrcode.viewfinder"
                )
            }
        } label: {
            Image(systemName: "plus")
                .font(
                    .system(
                        size: 24,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.white)
                .frame(
                    width: 58,
                    height: 58
                )
                .background {
                    Circle()
                        .fill(Color.accentColor)
                }
                .shadow(
                    color: Color.black.opacity(0.3),
                    radius: 8,
                    x: 0,
                    y: 4
                )
        }
        .accessibilityLabel("New conversation")
    }

    private func announceIdentity() {
        print("RETICULUM ANNOUNCE BUTTON PRESSED")

        LXMFManager.shared.announceIdentity()

        showingAnnounceMessage = true
    }

    private var conversationTabBar: some View {
        HStack(spacing: 8) {
            tabButton(
                title: "Direct",
                systemImage: "person.fill",
                tab: .direct
            )

            tabButton(
                title: "Groups",
                systemImage: "person.3.fill",
                tab: .groups
            )
        }
        .padding(6)
        .frame(maxWidth: 280)
        .background(Material.ultraThin)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(
                    Color.secondary.opacity(0.2),
                    lineWidth: 1
                )
        }
        .shadow(
            color: Color.black.opacity(0.18),
            radius: 10,
            x: 0,
            y: 4
        )
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var createGroupSheet: some View {
        NavigationStack {
            Form {
                Section("Group Name") {
                    TextField(
                        "Enter group name",
                        text: $groupName
                    )
                }

                Section("Icon") {
                    HStack(spacing: 18) {
                        groupIconButton(
                            "person.3.fill"
                        )

                        groupIconButton(
                            "antenna.radiowaves.left.and.right"
                        )

                        groupIconButton(
                            "tent.fill"
                        )

                        groupIconButton(
                            "star.fill"
                        )
                    }
                }

                Section("Members") {
                    Text("No RNodes available yet")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        cancelCreateGroup()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Create") {
                        createGroup()
                    }
                    .disabled(
                        trimmedGroupName.isEmpty
                    )
                }
            }
        }
    }

    private var directConversations: some View {
        VStack(spacing: 0) {
            Group {
                if contactStore.contacts.isEmpty {
                    emptyState(
                        systemImage:
                            "person.crop.circle.badge.questionmark",
                        title: "No Contacts",
                        message:
                            "Add or discover an LXMF contact to start a direct conversation."
                    )
                } else {
                    List {
                    ForEach(sortedDirectContacts) {
                        contact in
                        NavigationLink {
                            MessagesView(
                                bluetooth: bluetooth,
                                contact: contact
                            )
                        } label: {
                            directConversationRow(
                                conversation(
                                    for: contact
                                )
                            )
                        }
                        .contextMenu {
                            Button(
                                "Edit Contact",
                                systemImage: "pencil"
                            ) {
                                contactPendingEdit =
                                    contact
                            }

                            Button(
                                "Delete Chat",
                                systemImage: "trash",
                                role: .destructive
                            ) {
                                contactPendingDeletion =
                                    contact
                            }
                        }
                    }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private var sortedDirectContacts: [LXMFContact] {
        contactStore.contacts.sorted {
            let firstDate = messageStore
                .latestMessage(
                    for: $0.destinationHash
                )?.date ?? $0.dateAdded
            let secondDate = messageStore
                .latestMessage(
                    for: $1.destinationHash
                )?.date ?? $1.dateAdded
            return firstDate > secondDate
        }
    }

    private func conversation(
        for contact: LXMFContact
    ) -> Conversation {
        let latest = messageStore.latestMessage(
            for: contact.destinationHash
        )

        return Conversation(
            id: contact.id,
            title: contact.displayName,
            lastMessage:
                latest?.text ??
                "Ready for LXMF messaging",
            lastActivity:
                latest?.date ??
                contact.dateAdded,
            unreadCount:
                messageStore.unreadCount(
                    for: contact.destinationHash
                )
        )
    }

    private var groupConversations: some View {
        Group {
            if groups.isEmpty {
                emptyState(
                    systemImage: "person.3.fill",
                    title: "No Groups",
                    message:
                        "Create a group to start messaging."
                )
            } else {
                List {
                    ForEach(groups) { group in
                        NavigationLink {
                            GroupChatView(
                                group: group
                            )
                        } label: {
                            groupConversationRow(
                                group
                            )
                        }
                        .contextMenu {
                            Button(
                                "Delete Group",
                                systemImage: "trash",
                                role: .destructive
                            ) {
                                groupPendingDeletion =
                                    group
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func directConversationRow(
        _ conversation: Conversation
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    "person.crop.circle.fill"
            )
            .font(.system(size: 42))
            .foregroundStyle(.blue)

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                HStack {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(
                        conversation.lastActivity
                            .formatted(
                                date: .omitted,
                                time: .shortened
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Text(conversation.lastMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if conversation.unreadCount > 0 {
                        Text(
                            "\(conversation.unreadCount)"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(
                            minWidth: 22,
                            minHeight: 22
                        )
                        .background {
                            Circle()
                                .fill(
                                    Color.accentColor
                                )
                        }
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func groupConversationRow(
        _ group: GroupConversation
    ) -> some View {
        let preview =
            latestGroupPreview(for: group)

        return HStack(spacing: 14) {
            Image(
                systemName: group.systemImage
            )
            .font(.title2)
            .frame(
                width: 44,
                height: 44
            )
            .background {
                Circle()
                    .fill(
                        Color.accentColor
                            .opacity(0.15)
                    )
            }

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(group.name)
                    .font(.headline)

                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var trimmedGroupName: String {
        groupName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func cancelCreateGroup() {
        showCreateGroup = false
        groupName = ""
        selectedGroupIcon = "person.3.fill"
    }

    private func createGroup() {
        guard !trimmedGroupName.isEmpty else {
            return
        }

        let newGroup = GroupConversation(
            name: trimmedGroupName,
            systemImage: selectedGroupIcon
        )

        groups.append(newGroup)
        saveGroups()

        selectedTab = .groups
        showCreateGroup = false
        groupName = ""
        selectedGroupIcon = "person.3.fill"
    }

    private func deleteDirectConversation(
        _ contact: LXMFContact
    ) {
        messageStore.deleteConversation(
            destinationHash: contact.destinationHash
        )
        contactStore.remove(contact)
        contactPendingDeletion = nil
    }

    private func deleteGroupConversation(
        _ group: GroupConversation
    ) {
        groups.removeAll {
            $0.id == group.id
        }
        saveGroups()

        let defaults = UserDefaults.standard
        defaults.removeObject(
            forKey:
                "groupMessages-\(group.id.uuidString)"
        )
        defaults.removeObject(
            forKey:
                "savedGroupMessages_\(group.id.uuidString)"
        )
        groupPendingDeletion = nil
    }

    private func groupIconButton(
        _ systemImage: String
    ) -> some View {
        Button {
            selectedGroupIcon = systemImage
        } label: {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(
                    width: 44,
                    height: 44
                )
                .background {
                    Circle()
                        .fill(
                            selectedGroupIcon
                                == systemImage
                            ? Color.accentColor
                                .opacity(0.2)
                            : Color.secondary
                                .opacity(0.1)
                        )
                }
                .overlay {
                    if selectedGroupIcon
                        == systemImage {
                        Circle()
                            .stroke(
                                Color.accentColor,
                                lineWidth: 2
                            )
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func emptyState(
        systemImage: String,
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2.bold())

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()
        }
    }

    private static func loadGroups()
        -> [GroupConversation] {
        guard
            let data =
                UserDefaults.standard.data(
                    forKey:
                        "savedGroupConversations"
                ),
            let decodedGroups =
                try? JSONDecoder().decode(
                    [GroupConversation].self,
                    from: data
                )
        else {
            return []
        }

        return decodedGroups
    }

    private func saveGroups() {
        guard
            let data =
                try? JSONEncoder().encode(
                    groups
                )
        else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey:
                "savedGroupConversations"
        )
    }

    private func latestDirectPreview() -> (
        text: String,
        date: Date
    ) {
        guard
            let data =
                UserDefaults.standard.data(
                    forKey:
                        "savedDirectMessages"
                ),
            let savedMessages =
                try? JSONDecoder().decode(
                    [ChatMessage].self,
                    from: data
                ),
            let latestMessage =
                savedMessages.last
        else {
            return (
                "Ready for direct messaging",
                Date()
            )
        }

        switch latestMessage.type {
        case .text:
            return (
                latestMessage.text,
                latestMessage.date
            )

        case .photo:
            return (
                "📷 Photo",
                latestMessage.date
            )

        case .file:
            return (
                "📄 \(latestMessage.attachmentName ?? "File")",
                latestMessage.date
            )

        default:
            return (
                latestMessage.text.isEmpty
                    ? "New message"
                    : latestMessage.text,
                latestMessage.date
            )
        }
    }

    private func latestGroupPreview(
        for group: GroupConversation
    ) -> String {
        let storageKey =
            "savedGroupMessages_\(group.id.uuidString)"

        guard
            let data =
                UserDefaults.standard.data(
                    forKey: storageKey
                ),
            let savedMessages =
                try? JSONDecoder().decode(
                    [Message].self,
                    from: data
                ),
            let latestMessage =
                savedMessages.last
        else {
            return "No messages yet"
        }

        switch latestMessage.type {
        case .text:
            return latestMessage.text

        case .photo:
            return "📷 Photo"

        case .file:
            return
                "📄 \(latestMessage.attachmentName ?? "File")"

        @unknown default:
            return "New message"
        }
    }

    private func tabButton(
        title: String,
        systemImage: String,
        tab: ConversationTab
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(
                title,
                systemImage: systemImage
            )
            .font(
                .subheadline.weight(
                    .semibold
                )
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(
                selectedTab == tab
                    ? Color.accentColor
                    : Color.secondary
            )
            .background {
                if selectedTab == tab {
                    Capsule()
                        .fill(
                            Color.accentColor
                                .opacity(0.15)
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private enum ConversationTab {
    case direct
    case groups
}

struct GroupConversation:
    Identifiable,
    Codable {
    let id: UUID
    let name: String
    let systemImage: String

    init(
        id: UUID = UUID(),
        name: String,
        systemImage: String
    ) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
    }
}

#Preview {
    NavigationStack {
        ConversationsView(
            bluetooth: BluetoothManager()
        )
    }
}
