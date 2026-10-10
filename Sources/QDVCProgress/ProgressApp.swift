import AppKit
import SwiftUI

@main
struct ProgressApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        // One main window, like a single spreadsheet.
        Window("QDVC Progress", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 480)
                .onAppear {
                    appDelegate.model = model
                    model.startUp()
                }
        }
        .defaultSize(width: 1320, height: 800)
        .commands {
            ProgressCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than
        // from the .app bundle, so the app gets a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.flushSaves()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
