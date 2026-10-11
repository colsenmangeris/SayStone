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
                if DevelopmentRuntime.isUITesting {
                    UtilityWorkspaceView(coordinator: MacUtilityCoordinator.shared)
                        .onAppear {
                            DispatchQueue.main.async {
                                NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main-") == true })?.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                } else {
                    ContentView()
                        .environmentObject(self.menuBarManager)
                        .environmentObject(self.appServices)
                }
            }
        }
        .defaultSize(width: 1000, height: 700)
        // Synthetic tests must start with a workspace even when macOS has
        // retained a previously closed window. Normal launches keep SwiftUI's
        // default launch and restoration behavior.
        .defaultLaunchBehavior(DevelopmentRuntime.isUITesting ? .presented : .automatic)
        .restorationBehavior(DevelopmentRuntime.isUITesting ? .disabled : .automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    self.menuBarManager.openPreferencesFromUI()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Utilities") {
                Button("Command Palette…") { MacUtilityCoordinator.shared.show() }
                Button("Clipboard Library…") { MacUtilityCoordinator.shared.show(tab: "clipboard") }
                Button("Workflows…") { MacUtilityCoordinator.shared.show(tab: "workflows") }
                Button("Utility Shortcuts…") { MacUtilityCoordinator.shared.show(tab: "shortcuts") }
            }
        }
    }
}
