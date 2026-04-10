import Foundation
import Testing
@testable import NotesCurator

struct WorkspacePresentationTests {
    @Test
    func templateLibraryExposesLatexImportEntryAndReviewActions() {
        let actions = TemplateLibraryPresentation.availableActions(hasPendingImport: true)

        #expect(actions.contains("Import LaTeX Template"))
        #expect(actions.contains("Use Template"))
        #expect(actions.contains("Adjust Type"))
    }

    @Test
    func templateLibraryDefaultsToExpandedContentAndCollapsedVisualSections() {
        #expect(TemplateLibraryPresentation.startsExpanded(for: .content))
        #expect(TemplateLibraryPresentation.startsExpanded(for: .visual) == false)
        #expect(TemplateLibraryPresentation.sectionTitle(for: .content, count: 8) == "Content Templates (8)")
        #expect(TemplateLibraryPresentation.sectionTitle(for: .visual, count: 10) == "Visual Templates (10)")
    }

    @Test
    func templateLibraryStructuralPreviewDifferentiatesCoreContentPresets() throws {
        let formal = try #require(Template.builtinContentTemplate(named: "Formal Document", goalType: .formalDocument))
        let studyGuide = try #require(Template.builtinContentTemplate(named: "Study Guide", goalType: .structuredNotes))
        let technical = try #require(Template.builtinContentTemplate(named: "Technical Deep Dive", goalType: .formalDocument))

        let formalPreview = TemplateLibraryPresentation.structuralPreview(for: formal)
        let studyGuidePreview = TemplateLibraryPresentation.structuralPreview(for: studyGuide)
        let technicalPreview = TemplateLibraryPresentation.structuralPreview(for: technical)

        #expect(formalPreview.rows.contains { $0.kind == .calloutBox })
        #expect(studyGuidePreview.rows.contains { $0.kind == .examBox })
        #expect(technicalPreview.rows.contains { $0.kind == .codeBox })
        #expect(formalPreview != studyGuidePreview)
        #expect(studyGuidePreview != technicalPreview)
    }

    @Test
    func homeSurfacePrefersWorkspacesQuickActionsAndCurrentWork() {
        let sections = HomeSurfacePolicy.defaultSections(hasSavedSession: true)
        #expect(sections == [.workspaces, .quickActions, .currentWork])
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
        let resting = DraftCardPresentation(titleLineLimit: 3, summaryLineLimit: 2, showsDangerAction: false)
        let hovered = DraftCardPresentation(titleLineLimit: 3, summaryLineLimit: 2, showsDangerAction: true)
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
        #expect(presentation.titleLineLimit == 3)
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
        #expect(previewSections.map(\.title) == ["Document Summary"])
        #expect(previewSections.first(where: { $0.title == "Document Summary" })?.startsExpanded == true)
        #expect(exportSections.first(where: { $0.title == "Latest Export" })?.startsExpanded == true)
    }

    @Test
    func statusStripAllowsReturningToPreviousReviewStates() {
        #expect(FocusCanvasStageNavigation.destination(for: .preview, from: .export) == .preview)
        #expect(FocusCanvasStageNavigation.destination(for: .editing, from: .preview) == .editing)
        #expect(FocusCanvasStageNavigation.destination(for: .intake, from: .export) == nil)
    }

    @Test
    func workspaceCustomizationSubtitleAllowsExplicitEditsIncludingBlankValues() {
        #expect(WorkspaceCustomizationPresentation.resolvedSubtitle("  New purpose  ") == "New purpose")
        #expect(WorkspaceCustomizationPresentation.resolvedSubtitle("   ") == "")
    }

    @Test
    func workspaceCustomizationSubtitleEditorKeepsChromeOutOfTheHitTarget() {
        #expect(WorkspaceCustomizationPresentation.subtitleBorderAllowsHitTesting == false)
        #expect(WorkspaceCustomizationPresentation.subtitleEditorMinHeight >= 100)
        #expect(WorkspaceCustomizationPresentation.usesNativeTextViewForSubtitleEditing == true)
    }

    @Test
    func workspaceCustomizationLetsSubtitleTakeFocusAfterInitialTitleFocus() {
        #expect(WorkspaceCustomizationPresentation.initialFocusedField == .title)
        #expect(
            WorkspaceCustomizationPresentation.focusTarget(afterSelecting: .subtitle) == .subtitle
        )
    }

    @Test
    func workspaceDetailPrefersLiveWorkspaceValuesOverFallbackSnapshot() {
        let workspaceID = UUID()
        let fallback = Workspace(id: workspaceID, name: "Ideas", subtitle: "Old subtitle", cover: .ocean)
        let updated = Workspace(id: workspaceID, name: "Ideas", subtitle: "Updated subtitle", cover: .ocean)

        let resolved = WorkspaceDetailPresentation.liveWorkspace(
            workspaceID: workspaceID,
            from: [updated],
            fallback: fallback
        )

        #expect(resolved.subtitle == "Updated subtitle")
    }
}
