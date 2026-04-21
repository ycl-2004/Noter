import AppKit
import SwiftUI

private enum NotesCuratorWindowID {
    static let main = "main"
}

@main
struct NotesCuratorApp: App {
    @NSApplicationDelegateAdaptor(NotesCuratorAppDelegate.self) private var appDelegate
    @State private var model = NotesCuratorBootstrap.makeModel()

    var body: some Scene {
        Window("Noter", id: NotesCuratorWindowID.main) {
            NotesCuratorRootView(model: model)
                .frame(minWidth: 1280, minHeight: 860)
                .background {
                    MainWindowOpenRegistrationView { action in
                        appDelegate.registerOpenMainWindowAction(action)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 920)
        .defaultLaunchBehavior(.presented)
    }
}

@MainActor
final class NotesCuratorAppDelegate: NSObject, NSApplicationDelegate {
    private let lifecycle = NotesCuratorWindowLifecycleController()
    private var openMainWindowAction: (() -> Void)?

    override init() {
        super.init()
        lifecycle.activateWindow = { [weak self] in
            self?.activateAppWindow() ?? false
        }
        lifecycle.reopenMainWindow = { [weak self] in
            self?.openMainWindowAction?()
        }
    }

    func registerOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = activateAppWindow()
        DispatchQueue.main.async {
            _ = self.activateAppWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            _ = self.activateAppWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        lifecycle.applicationDidBecomeActive()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if lifecycle.applicationShouldHandleReopen(hasVisibleWindows: flag) {
            DispatchQueue.main.async {
                _ = self.activateAppWindow()
            }
        }
        return true
    }

    @discardableResult
    private func activateAppWindow() -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        guard let window = primaryWindow else { return false }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    private var primaryWindow: NSWindow? {
        NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey })
            ?? NSApp.windows.first(where: { $0.isMiniaturized && $0.canBecomeKey })
            ?? NSApp.windows.first(where: { $0.canBecomeKey })
            ?? NSApp.windows.first
    }
}

@MainActor
final class NotesCuratorWindowLifecycleController {
    var activateWindow: () -> Bool = { false }
    var reopenMainWindow: () -> Void = {}

    func applicationDidBecomeActive() {
        _ = activateWindow()
    }

    @discardableResult
    func applicationShouldHandleReopen(hasVisibleWindows _: Bool) -> Bool {
        if activateWindow() {
            return false
        }

        reopenMainWindow()
        return true
    }
}

private struct MainWindowOpenRegistrationView: View {
    @Environment(\.openWindow) private var openWindow

    let register: (@escaping () -> Void) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .task {
                register {
                    openWindow(id: NotesCuratorWindowID.main)
                }
            }
    }
}
