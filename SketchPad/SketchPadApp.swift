import SwiftUI

@main
struct SketchPadApp: App {
    @StateObject private var store = DrawingStore()

    var body: some Scene {
        WindowGroup {
            DrawingScreen()
                .environmentObject(store)
        }
    }
}
