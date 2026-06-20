import SwiftUI

@main
struct ShiranganaApp: App {
    var body: some Scene {
        WindowGroup {
            CameraScreen()
                .preferredColorScheme(.light)
        }
    }
}
