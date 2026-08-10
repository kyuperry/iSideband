//
//  iSidebandApp.swift
//  iSideband
//
//  Created by Kyle Perry on 7/19/26.
//

import SwiftUI

@main
struct iSidebandApp: App {

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var lxmfManager = LXMFManager.shared
    @StateObject private var bluetooth = BluetoothManager()

    init() {
        NotificationPreferences.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                bluetooth: bluetooth
            )
                .environmentObject(lxmfManager)
                .task {
                    lxmfManager.start(
                        bluetooth: bluetooth
                    )
                    LXMFDiscoveryMode.shared.configure(
                        manager: lxmfManager,
                        bluetooth: bluetooth
                    )
                    RNodeLiveActivityManager.shared.configure(bluetooth: bluetooth)
                    RNodeLiveActivityManager.shared.setAppIsActive(scenePhase == .active)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    RNodeLiveActivityManager.shared.setAppIsActive(newPhase == .active)
                }
        }
    }
}
