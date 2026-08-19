import Foundation
import AppKit

let bundleURL = Bundle.main.bundleURL
let vaultURL = bundleURL.deletingLastPathComponent()
let htmlURL = vaultURL
    .appendingPathComponent("アプリ本体")
    .appendingPathComponent("PTCGL-Pokemon-Coach")
    .appendingPathComponent("index.html")

guard FileManager.default.fileExists(atPath: htmlURL.path) else {
    let alert = NSAlert()
    alert.messageText = "PTCGLポケカコーチを開けません"
    alert.informativeText = "本体HTMLが見つかりません。"
    alert.runModal()
    exit(1)
}

var parts = URLComponents(url: htmlURL, resolvingAgainstBaseURL: false)!
parts.queryItems = [URLQueryItem(name: "app", value: "1")]

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
process.arguments = [
    "-na", "Google Chrome", "--args",
    "--profile-directory=Default",
    "--app=\(parts.url!.absoluteString)"
]
try process.run()
process.waitUntilExit()
