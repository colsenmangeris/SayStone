//
//  fluidApp.swift
//  fluid
//
//  Created by Barathwaj Anandan on 7/30/25.
//

import AppKit
import ApplicationServices
import SwiftUI

@main
struct FluidApp: App {
    @StateObject private var menuBarManager: MenuBarManager
    @StateObject private var appServices: AppServices
    @ObservedObject private var settings: SettingsStore
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        do {
            try AppStorage.prepareDevelopmentStorage()
        } catch {
            fatalError("Could not prepare isolated development storage: \(error.localizedDescription)")
        }
        _settings = ObservedObject(wrappedValue: SettingsStore.shared)
        _menuBarManager = StateObject(wrappedValue: MenuBarManager())
        _appServices = StateObject(wrappedValue: AppServices.shared)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            AdaptiveAppTheme(accent: self.settings.accentColor) {
                ContentView()
                    .environmentObject(self.menuBarManager)
                    .environmentObject(self.appServices)
            }
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    self.menuBarManager.openPreferencesFromUI()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
