//
//  iSidebandApp.swift
//  iSideband
//
//  Created by Kyle Perry on 7/19/26.
//

import SwiftUI

@main
struct iSidebandApp: App {
    @StateObject private var lxmfManager =
        LXMFManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(lxmfManager)
                .task {
                    lxmfManager.start()
                }
        }
    }
}
