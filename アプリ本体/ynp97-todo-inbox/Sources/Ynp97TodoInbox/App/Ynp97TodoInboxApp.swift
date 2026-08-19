import AppKit
import SwiftUI

@main
struct Ynp97TodoInboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TodoStore()

    var body: some Scene {
        WindowGroup("TODOインボックス") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 920, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("ynp97相談パックをコピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.ynpPack(), forType: .string)
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
