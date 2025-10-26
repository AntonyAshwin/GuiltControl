//
//  The_Guilt_ControlApp.swift
//  The Guilt Control
//
//  Created by Ashwin, Antony on 26/10/25.
//

import SwiftUI

@main
struct The_Guilt_ControlApp: App {
    @StateObject private var store = TapHistoryStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
