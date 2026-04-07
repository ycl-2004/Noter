import Testing
@testable import NotesCurator

struct WorkspacePresentationTests {
    @Test
    func homeSurfacePrefersResumeRecentAndQuickActions() {
        let sections = HomeSurfacePolicy.defaultSections(hasSavedSession: true)
        #expect(sections == [.resume, .recentActivity, .quickActions])
    }

    @Test
    func focusCanvasStagesMapCurrentFlowIntoCompletedCurrentAndUpcomingStates() {
        let items = FocusCanvasStageModel.items(currentFlow: .preview)
        #expect(items.map(\.stage) == [.intake, .processing, .editing, .preview, .export])
        #expect(items.first(where: { $0.stage == .editing })?.state == .completed)
        #expect(items.first(where: { $0.stage == .preview })?.state == .current)
        #expect(items.first(where: { $0.stage == .export })?.state == .upcoming)
    }

    @Test
    func draftCardPresentationHidesDangerActionsUntilHover() {
        let resting = DraftCardPresentation(summaryLineLimit: 2, showsDangerAction: false)
        let hovered = DraftCardPresentation(summaryLineLimit: 2, showsDangerAction: true)
        #expect(resting.showsDangerAction == false)
        #expect(hovered.showsDangerAction == true)
    }

    @Test
    func reviewSurfaceModeSeparatesPreviewAndExportInspectorContent() {
        #expect(ReviewSurfaceMode.preview.inspectorTitle == "Review")
        #expect(ReviewSurfaceMode.export.inspectorTitle == "Export")
    }
}
