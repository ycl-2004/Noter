import AppKit
import SwiftUI

@main
struct NotesCuratorApp: App {
    @NSApplicationDelegateAdaptor(NotesCuratorAppDelegate.self) private var appDelegate
    @State private var model = NotesCuratorBootstrap.makeModel()

    var body: some Scene {
        WindowGroup {
            NotesCuratorRootView(model: model)
                .frame(minWidth: 1280, minHeight: 860)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 920)
    }
}

@MainActor
final class NotesCuratorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        activateAppWindow()
        DispatchQueue.main.async {
            self.activateAppWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.activateAppWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activateAppWindow()
    }

    private func activateAppWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        guard let window = NSApp.windows.first(where: { $0.canBecomeKey }) ?? NSApp.windows.first else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
