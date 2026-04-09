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
