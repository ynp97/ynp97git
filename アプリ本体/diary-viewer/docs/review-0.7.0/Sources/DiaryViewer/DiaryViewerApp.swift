import SwiftUI

// MARK: - App Entry Point

@main
struct DiaryViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowStyle(.titleBar)
        // ★ .contentSize から .contentMinSize へ変更（2026-07-31）。
        //   .contentSize はウィンドウの最大サイズまで中身の理想サイズに縛るため、
        //   横に広げられない・フルスクリーンにしても中身が伸びない状態だった
        //   （本人の言う「画面の拡張」ができない件）。
        //   .contentMinSize は下限だけを決め、上限は自由になる。
        .windowResizability(.contentMinSize)
    }
}
