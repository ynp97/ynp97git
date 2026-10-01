import AppKit
import WebKit

final class ReaderApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let screen = NSScreen.screens.first ?? NSScreen.main!
        let url = URL(string: "http://127.0.0.1:19797/reader")!
        var frame = screen.visibleFrame
        frame.size.width = floor(frame.width * 0.45)
        if args.count == 6,
           let requestedURL = URL(string: args[1]),
           requestedURL == url,
           let left = Double(args[2]), let top = Double(args[3]),
           let width = Double(args[4]), let height = Double(args[5]),
           width > 0, height > 0 {
            frame = NSRect(x: left, y: screen.frame.maxY - top - height,
                           width: width, height: height)
        }
        let reader = WKWebView(frame: NSRect(origin: .zero, size: frame.size))
        reader.autoresizingMask = [.width, .height]
        reader.load(URLRequest(url: url))

        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "早天原稿"
        window.contentView = reader
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = ReaderApp()
app.delegate = delegate
app.run()
