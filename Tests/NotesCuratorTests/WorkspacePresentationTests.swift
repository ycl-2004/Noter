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

    @Test
    func workspaceShellRemovesLocalLibraryCategories() {
        #expect(WorkspaceShellPolicy.showsLocalCategoryTabs == false)
    }

    @Test
    func compactSidebarWorkspaceBadgeUsesShortUtilityCopy() {
        let badge = SidebarWorkspaceBadgePresentation.compact(
            workspaceName: "Research",
            draftCount: 3
        )
        #expect(badge.title == "Research")
        #expect(badge.detail == "3 drafts")
    }

    @Test
    func focusCanvasHeaderUsesBreadcrumbStyleIdentity() {
        let header = FocusCanvasHeaderPresentation(
            workspaceName: "Security",
            noteTitle: "Delegatecall 机制详解",
            showsLargeDuplicatedTitle: false
        )
        #expect(header.showsLargeDuplicatedTitle == false)
    }

    @Test
    func stageControlAlwaysRendersFiveWorkflowStages() {
        let items = FocusCanvasStageModel.items(currentFlow: .editing)
        #expect(items.count == 5)
    }

    @Test
    func previewModeUsesReviewInspectorAndExportModeUsesExportInspector() {
        #expect(ReviewSurfaceMode.preview.inspectorTitle == "Review")
        #expect(ReviewSurfaceMode.export.inspectorTitle == "Export")
    }

    @Test
    func reviewSurfaceUsesPersistentPrimaryActionLabels() {
        #expect(ReviewSurfaceActionLabels.preview.primary == "Continue to Export")
        #expect(ReviewSurfaceActionLabels.export.primary == "Export to Folder")
    }

    @Test
    func draftCardsClampSummaryToTwoLinesInCompactContexts() {
        let presentation = DraftCardPresentation.compactResting
        #expect(presentation.summaryLineLimit == 2)
    }

    @Test
    func dangerActionsStayHiddenInRestingCardState() {
        let presentation = DraftCardPresentation.compactResting
        #expect(presentation.showsDangerAction == false)
    }

    @Test
    func reviewSurfacesPromoteNavigationActionsIntoFlowHeader() {
        let preview = FlowHeaderActionSet.actions(for: .preview)
        let export = FlowHeaderActionSet.actions(for: .export)

        #expect(preview?.placement == .trailing)
        #expect(export?.placement == .trailing)
        #expect(FlowHeaderActionSet.actions(for: .editing) == nil)
    }

    @Test
    func reviewSurfacesSupportCollapsibleInspectorsWithCompactDefaults() {
        let previewSections = ReviewSurfaceChrome.inspectorSections(for: .preview, hasExportResult: false)
        let exportSections = ReviewSurfaceChrome.inspectorSections(for: .export, hasExportResult: true)

        #expect(ReviewSurfaceChrome.supportsInspectorCollapse(for: .preview))
        #expect(previewSections.first(where: { $0.title == "Document Summary" })?.startsExpanded == false)
        #expect(previewSections.first(where: { $0.title == "Format" })?.startsExpanded == true)
        #expect(exportSections.first(where: { $0.title == "Latest Export" })?.startsExpanded == true)
    }

    @Test
    func statusStripAllowsReturningToPreviousReviewStates() {
        #expect(FocusCanvasStageNavigation.destination(for: .preview, from: .export) == .preview)
        #expect(FocusCanvasStageNavigation.destination(for: .editing, from: .preview) == .editing)
        #expect(FocusCanvasStageNavigation.destination(for: .intake, from: .export) == nil)
    }
}
