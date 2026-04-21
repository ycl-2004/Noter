import Testing
@testable import NotesCurator

@MainActor
struct NotesCuratorAppLifecycleTests {
    @Test
    func dockReopenRequestsMainWindowWhenNoWindowIsAvailable() {
        let controller = NotesCuratorWindowLifecycleController()
        var reopenRequests = 0

        controller.activateWindow = {
            false
        }
        controller.reopenMainWindow = {
            reopenRequests += 1
        }

        let handled = controller.applicationShouldHandleReopen(hasVisibleWindows: false)

        #expect(handled)
        #expect(reopenRequests == 1)
    }

    @Test
    func dockReopenDoesNotSpawnNewWindowWhenExistingWindowCanBeActivated() {
        let controller = NotesCuratorWindowLifecycleController()
        var reopenRequests = 0

        controller.activateWindow = { true }
        controller.reopenMainWindow = {
            reopenRequests += 1
        }

        let handled = controller.applicationShouldHandleReopen(hasVisibleWindows: true)

        #expect(handled == false)
        #expect(reopenRequests == 0)
    }
}
