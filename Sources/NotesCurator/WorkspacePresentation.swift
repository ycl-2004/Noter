import Foundation

enum HomeSurfaceSection: Equatable {
    case resume
    case recentActivity
    case quickActions
}

enum FocusCanvasStageState: Equatable {
    case completed
    case current
    case upcoming
}

struct FocusCanvasStageItem: Equatable {
    let stage: WorkspaceFlowStage
    let state: FocusCanvasStageState
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
    let summaryLineLimit: Int
    let showsDangerAction: Bool
}

enum HomeSurfacePolicy {
    static func defaultSections(hasSavedSession: Bool) -> [HomeSurfaceSection] {
        hasSavedSession ? [.resume, .recentActivity, .quickActions] : [.recentActivity, .quickActions]
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
            return FocusCanvasStageItem(stage: stage, state: state)
        }
    }
}
