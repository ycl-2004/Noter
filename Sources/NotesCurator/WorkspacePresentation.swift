import Foundation

enum HomeSurfaceSection: Equatable {
    case workspaces
    case quickActions
    case currentWork
}

enum FocusCanvasStageState: Equatable {
    case completed
    case current
    case upcoming
}

struct FocusCanvasStageItem: Equatable {
    let stage: WorkspaceFlowStage
    let state: FocusCanvasStageState
    let isNavigable: Bool
}

enum ReviewSurfaceMode: Equatable {
    case preview
    case export

    var inspectorTitle: String {
        switch self {
        case .preview:
            "Review"
        case .export:
            "Export"
        }
    }
}

struct DraftCardPresentation: Equatable {
    let titleLineLimit: Int
    let summaryLineLimit: Int
    let showsDangerAction: Bool
}

extension DraftCardPresentation {
    static let compactResting = Self(titleLineLimit: 3, summaryLineLimit: 2, showsDangerAction: false)
}

enum WorkspaceShellPolicy {
    static let showsLocalCategoryTabs = false
}

struct SidebarWorkspaceBadgePresentation: Equatable {
    let title: String
    let detail: String

    static func compact(workspaceName: String, draftCount: Int) -> Self {
        .init(title: workspaceName, detail: "\(draftCount) drafts")
    }
}

struct FocusCanvasHeaderPresentation: Equatable {
    let workspaceName: String
    let noteTitle: String
    let showsLargeDuplicatedTitle: Bool
}

struct ReviewSurfaceActionLabels: Equatable {
    let primary: String
    let secondary: String

    static let preview = Self(primary: "Continue to Export", secondary: "Back to Editing")
    static let export = Self(primary: "Export to Folder", secondary: "Back to Preview")
}

enum FlowHeaderActionPlacement: Equatable {
    case trailing
}

struct FlowHeaderActionSet: Equatable {
    let primary: String
    let secondary: String
    let placement: FlowHeaderActionPlacement

    static func actions(for stage: WorkspaceFlowStage) -> Self? {
        switch stage {
        case .preview:
            return .init(
                primary: ReviewSurfaceActionLabels.preview.primary,
                secondary: ReviewSurfaceActionLabels.preview.secondary,
                placement: .trailing
            )
        case .export:
            return .init(
                primary: ReviewSurfaceActionLabels.export.primary,
                secondary: ReviewSurfaceActionLabels.export.secondary,
                placement: .trailing
            )
        case .intake, .processing, .editing:
            return nil
        }
    }
}

struct ReviewInspectorSection: Equatable {
    let title: String
    let startsExpanded: Bool
}

enum WorkspaceCustomizationPresentation {
    enum FocusField: Equatable {
        case title
        case subtitle
    }

    static let subtitleBorderAllowsHitTesting = false
    static let subtitleEditorMinHeight: CGFloat = 108
    static let usesNativeTextViewForSubtitleEditing = true
    static let initialFocusedField: FocusField = .title

    static func focusTarget(afterSelecting field: FocusField) -> FocusField {
        field
    }

    static func resolvedSubtitle(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WorkspaceDetailPresentation {
    static func liveWorkspace(workspaceID: UUID, from workspaces: [Workspace], fallback: Workspace) -> Workspace {
        workspaces.first(where: { $0.id == workspaceID }) ?? fallback
    }
}

enum ReviewSurfaceChrome {
    static func supportsInspectorCollapse(for mode: ReviewSurfaceMode) -> Bool {
        switch mode {
        case .preview, .export:
            return true
        }
    }

    static func inspectorSections(for mode: ReviewSurfaceMode, hasExportResult: Bool) -> [ReviewInspectorSection] {
        switch mode {
        case .preview:
            return [
                .init(title: "Document Summary", startsExpanded: true)
            ]
        case .export:
            var sections: [ReviewInspectorSection] = [
                .init(title: "Document Summary", startsExpanded: false),
                .init(title: "Format", startsExpanded: true),
                .init(title: "Visual Template", startsExpanded: false),
                .init(title: "Current Output Language", startsExpanded: false),
                .init(title: "Export Readiness", startsExpanded: false),
                .init(title: "Save Template", startsExpanded: false)
            ]
            if hasExportResult {
                sections.insert(.init(title: "Latest Export", startsExpanded: true), at: 5)
            }
            return sections
        }
    }
}

enum FocusCanvasStageNavigation {
    static func destination(for tappedStage: WorkspaceFlowStage, from currentFlow: WorkspaceFlowStage) -> WorkspaceFlowStage? {
        switch (currentFlow, tappedStage) {
        case (.preview, .editing):
            return .editing
        case (.export, .preview):
            return .preview
        case (.export, .editing):
            return .editing
        default:
            return nil
        }
    }
}

enum HomeSurfacePolicy {
    static func defaultSections(hasSavedSession: Bool) -> [HomeSurfaceSection] {
        _ = hasSavedSession
        return [.workspaces, .quickActions, .currentWork]
    }
}

enum TemplateLibraryPresentation {
    static func availableActions(hasPendingImport: Bool) -> [String] {
        var actions = ["Import LaTeX Template"]
        if hasPendingImport {
            actions.append("Use Template")
            actions.append("Adjust Type")
        }
        return actions
    }

    static func startsExpanded(for kind: TemplateKind) -> Bool {
        switch kind {
        case .content:
            return true
        case .visual:
            return false
        }
    }

    static func sectionTitle(for kind: TemplateKind, count: Int) -> String {
        switch kind {
        case .content:
            return "Content Templates (\(count))"
        case .visual:
            return "Visual Templates (\(count))"
        }
    }

    static func structuralPreview(for template: Template) -> TemplateStructuralPreview {
        guard template.kind == .content else {
            return .fallback
        }

        guard let pack = try? template.templatePack() else {
            return .fallback
        }

        var rows: [TemplateStructuralPreviewRow] = []
        var seenKinds = Set<TemplateStructuralPreviewKind>()

        for block in pack.layout.blocks {
            guard let row = previewRow(for: block) else { continue }
            guard seenKinds.contains(row.kind) == false else { continue }
            rows.append(row)
            seenKinds.insert(row.kind)
        }

        let curatedRows = prioritizedPreviewRows(from: rows)
        return curatedRows.isEmpty ? .fallback : TemplateStructuralPreview(rows: curatedRows)
    }

    private static func previewRow(for block: TemplateBlockSpec) -> TemplateStructuralPreviewRow? {
        let binding = (block.fieldBinding ?? "").lowercased()
        let variant = TemplateBlockStyleVariant(rawValue: block.styleVariant) ?? .standard

        switch block.blockType {
        case .title:
            return nil
        case .summary:
            return TemplateStructuralPreviewRow(kind: .summary)
        case .section:
            return TemplateStructuralPreviewRow(kind: .section)
        case .keyPoints:
            return TemplateStructuralPreviewRow(kind: .bulletList)
        case .cueQuestions, .reviewQuestions, .actionItems:
            return TemplateStructuralPreviewRow(kind: .checklist)
        case .glossary:
            return TemplateStructuralPreviewRow(kind: .glossary)
        case .studyCards:
            return TemplateStructuralPreviewRow(kind: .flashcards)
        case .warningBox:
            return TemplateStructuralPreviewRow(kind: .warningBox)
        case .exercise:
            if binding.contains("example") {
                return TemplateStructuralPreviewRow(kind: .calloutBox)
            }
            return TemplateStructuralPreviewRow(kind: .examBox)
        case .callouts:
            if binding.contains("code") || variant == .code {
                return TemplateStructuralPreviewRow(kind: .codeBox)
            }
            if binding.contains("warning") || variant == .warning {
                return TemplateStructuralPreviewRow(kind: .warningBox)
            }
            if binding.contains("exam") || variant == .exam {
                return TemplateStructuralPreviewRow(kind: .examBox)
            }
            return TemplateStructuralPreviewRow(kind: .calloutBox)
        }
    }

    private static func prioritizedPreviewRows(from rows: [TemplateStructuralPreviewRow]) -> [TemplateStructuralPreviewRow] {
        guard rows.count > 5 else { return rows }

        let mustKeep: Set<TemplateStructuralPreviewKind> = [
            .summary,
            .section,
            .codeBox,
            .examBox,
            .flashcards,
            .glossary
        ]
        let preferred: [TemplateStructuralPreviewKind] = [
            .calloutBox,
            .warningBox,
            .checklist,
            .bulletList
        ]

        var selectedKinds = Set(rows.compactMap { mustKeep.contains($0.kind) ? $0.kind : nil })
        var selectedRows = rows.filter { selectedKinds.contains($0.kind) }

        for kind in preferred where selectedRows.count < 5 {
            guard let row = rows.first(where: { $0.kind == kind }), selectedKinds.contains(kind) == false else { continue }
            selectedRows.append(row)
            selectedKinds.insert(kind)
        }

        for row in rows where selectedRows.count < 5 {
            guard selectedKinds.contains(row.kind) == false else { continue }
            selectedRows.append(row)
            selectedKinds.insert(row.kind)
        }

        return rows.filter { selectedKinds.contains($0.kind) }.prefix(5).map { $0 }
    }
}

struct TemplateStructuralPreview: Equatable, Sendable {
    var rows: [TemplateStructuralPreviewRow]

    static let fallback = Self(
        rows: [
            .init(kind: .summary),
            .init(kind: .section),
            .init(kind: .bulletList)
        ]
    )
}

struct TemplateStructuralPreviewRow: Equatable, Sendable {
    var kind: TemplateStructuralPreviewKind
}

enum TemplateStructuralPreviewKind: String, Equatable, Hashable, Sendable {
    case summary
    case section
    case bulletList
    case checklist
    case glossary
    case flashcards
    case calloutBox
    case codeBox
    case warningBox
    case examBox
}

enum FocusCanvasStageModel {
    static func items(currentFlow: WorkspaceFlowStage) -> [FocusCanvasStageItem] {
        let ordered: [WorkspaceFlowStage] = [.intake, .processing, .editing, .preview, .export]
        guard let currentIndex = ordered.firstIndex(of: currentFlow) else {
            return []
        }

        return ordered.enumerated().map { index, stage in
            let state: FocusCanvasStageState
            if index < currentIndex {
                state = .completed
            } else if index == currentIndex {
                state = .current
            } else {
                state = .upcoming
            }
            return FocusCanvasStageItem(
                stage: stage,
                state: state,
                isNavigable: FocusCanvasStageNavigation.destination(for: stage, from: currentFlow) != nil
            )
        }
    }
}
