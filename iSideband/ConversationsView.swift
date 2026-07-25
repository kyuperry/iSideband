import SwiftUI

struct ConversationsView: View {
    @ObservedObject var bluetooth: BluetoothManager
    
    @State private var selectedTab: ConversationTab = .direct
    @State private var showNewConversation = false
    @State private var showCreateGroup = false
    @State private var groupName = ""
    @State private var selectedGroupIcon = "person.3.fill"
    
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
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewConversation = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .confirmationDialog(
            "New Conversation",
            isPresented: $showNewConversation,
            titleVisibility: .visible
        ) {
            Button("Start Direct Chat") {
                selectedTab = .direct
            }
            
            Button("Create Group") {
                showCreateGroup = true
            }
            
            Button("Enter LXMF Address") {
                print("LXMF address entry selected")
            }
            
            Button("Scan QR Code") {
                print("QR scanner selected")
            }
            
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showCreateGroup) {
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
                            groupIconButton("person.3.fill")
                            groupIconButton(
                                "antenna.radiowaves.left.and.right"
                            )
                            groupIconButton("tent.fill")
                            groupIconButton("star.fill")
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
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showCreateGroup = false
                            groupName = ""
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            selectedTab = .groups
                            showCreateGroup = false
                        }
                        .disabled(
                            groupName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                    }
                }
            }
        }
    }
    
    private var directConversations: some View {
        Group {
            if bluetooth.connectedDeviceID != nil {
                List {
                    NavigationLink {
                        MessagesView(bluetooth: bluetooth)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            
                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                Text(
                                    bluetooth.connectedDeviceName
                                    ?? "Connected RNode"
                                )
                                .font(.headline)
                                
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                emptyState(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "No RNodes",
                    message: "Connected RNodes will appear here for direct messaging."
                )
            }
        }
    }
    
    private var groupConversations: some View {
        emptyState(
            systemImage: "person.3",
            title: "No Groups",
            message: "Group conversations will appear here after you create or join one."
        )
    }
    
    private func groupIconButton(
        _ systemImage: String
    ) -> some View {
        Button {
            selectedGroupIcon = systemImage
        } label: {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(
                            selectedGroupIcon == systemImage
                            ? Color.accentColor.opacity(0.2)
                            : Color.secondary.opacity(0.1)
                        )
                }
                .overlay {
                    if selectedGroupIcon == systemImage {
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
    private func tabButton(
        title: String,
        systemImage: String,
        tab: ConversationTab
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
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
                            .fill(Color.accentColor.opacity(0.15))
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

#Preview {
    NavigationStack {
        ConversationsView(
            bluetooth: BluetoothManager()
        )
    }
}
