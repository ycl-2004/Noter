import Foundation

enum RenderSurface: Sendable {
    case authoring
    case preview
    case export
}

struct RenderedTemplateDocument: Equatable, Sendable {
    var title: String
    var blocks: [RenderedTemplateBlock]
}

struct RenderedTemplateBlock: Equatable, Sendable, Identifiable {
    var id: UUID
    var blockType: TemplateBlockType
    var title: String
    var body: String?
    var items: [String]
    var placeholderText: String?
    var styleVariant: String
}

enum TemplatePackRenderer {
    static func render(
        document: StructuredDocument,
        pack: TemplatePack,
        surface: RenderSurface
    ) throws -> RenderedTemplateDocument {
        let blocks = pack.layout.blocks.flatMap { spec in
            makeBlocks(from: spec, document: document, surface: surface)
        }

        return RenderedTemplateDocument(
            title: document.title,
            blocks: blocks
        )
    }

    private static func makeBlocks(
        from spec: TemplateBlockSpec,
        document: StructuredDocument,
        surface: RenderSurface
    ) -> [RenderedTemplateBlock] {
        switch content(for: spec, document: document) {
        case let .text(text):
            return makeTextBlock(text, from: spec, surface: surface)
        case let .list(items):
            return makeListBlock(items, from: spec, surface: surface)
        case let .sections(sections):
            guard !sections.isEmpty else { return placeholderBlocks(for: spec, surface: surface) }
            return sections.map { section in
                RenderedTemplateBlock(
                    id: UUID(),
                    blockType: spec.blockType,
                    title: section.title,
                    body: section.body,
                    items: section.bulletPoints,
                    placeholderText: nil,
                    styleVariant: spec.styleVariant
                )
            }
        case let .callouts(callouts):
            guard !callouts.isEmpty else { return placeholderBlocks(for: spec, surface: surface) }
            return callouts.map { callout in
                RenderedTemplateBlock(
                    id: UUID(),
                    blockType: spec.blockType,
                    title: callout.title,
                    body: callout.body,
                    items: [],
                    placeholderText: nil,
                    styleVariant: spec.styleVariant
                )
            }
        case let .boxes(boxes):
            guard !boxes.isEmpty else { return placeholderBlocks(for: spec, surface: surface) }
            return boxes.map { box in
                let title = box.title.trimmed.isEmpty ? title(for: spec) : box.title.trimmed
                let body = box.body.trimmed
                let items = box.items.map(\.trimmed).filter { !$0.isEmpty }
                return RenderedTemplateBlock(
                    id: UUID(),
                    blockType: spec.blockType,
                    title: title,
                    body: body.isEmpty ? nil : body,
                    items: items,
                    placeholderText: nil,
                    styleVariant: spec.styleVariant
                )
            }
        case let .glossary(items):
            let lines = items.map { "**\($0.term)**: \($0.definition)" }
            return makeListBlock(lines, from: spec, surface: surface)
        case let .studyCards(cards):
            let lines = cards.flatMap { ["Q: \($0.question)", "A: \($0.answer)"] }
            return makeListBlock(lines, from: spec, surface: surface)
        }
    }

    private static func makeTextBlock(
        _ text: String,
        from spec: TemplateBlockSpec,
        surface: RenderSurface
    ) -> [RenderedTemplateBlock] {
        guard text.trimmed.isEmpty == false else { return placeholderBlocks(for: spec, surface: surface) }
        return [
            RenderedTemplateBlock(
                id: spec.id,
                blockType: spec.blockType,
                title: title(for: spec),
                body: text,
                items: [],
                placeholderText: nil,
                styleVariant: spec.styleVariant
            )
        ]
    }

    private static func makeListBlock(
        _ items: [String],
        from spec: TemplateBlockSpec,
        surface: RenderSurface
    ) -> [RenderedTemplateBlock] {
        let cleaned = items.map(\.trimmed).filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return placeholderBlocks(for: spec, surface: surface) }
        return [
            RenderedTemplateBlock(
                id: spec.id,
                blockType: spec.blockType,
                title: title(for: spec),
                body: nil,
                items: cleaned,
                placeholderText: nil,
                styleVariant: spec.styleVariant
            )
        ]
    }

    private static func placeholderBlocks(for spec: TemplateBlockSpec, surface: RenderSurface) -> [RenderedTemplateBlock] {
        switch spec.emptyBehavior.behavior(for: surface) {
        case .hide:
            return []
        case .show:
            return [
                RenderedTemplateBlock(
                    id: spec.id,
                    blockType: spec.blockType,
                    title: title(for: spec),
                    body: nil,
                    items: [],
                    placeholderText: nil,
                    styleVariant: spec.styleVariant
                )
            ]
        case .placeholder:
            return [
                RenderedTemplateBlock(
                    id: spec.id,
                    blockType: spec.blockType,
                    title: title(for: spec),
                    body: nil,
                    items: [],
                    placeholderText: "Add \(title(for: spec).lowercased())",
                    styleVariant: spec.styleVariant
                )
            ]
        }
    }

    private static func title(for spec: TemplateBlockSpec) -> String {
        if let titleOverride = spec.titleOverride?.trimmed, !titleOverride.isEmpty {
            return titleOverride
        }

        switch spec.blockType {
        case .title:
            return "Title"
        case .summary:
            return "Summary"
        case .section:
            return "Section"
        case .keyPoints:
            return "Key Points"
        case .cueQuestions:
            return "Cue Questions"
        case .callouts:
            return "Callouts"
        case .glossary:
            return "Glossary"
        case .studyCards:
            return "Study Cards"
        case .reviewQuestions:
            return "Review Questions"
        case .actionItems:
            return "Action Items"
        case .warningBox:
            return "Warnings"
        case .exercise:
            return "Exercises"
        }
    }

    private static func content(for spec: TemplateBlockSpec, document: StructuredDocument) -> RenderedTemplateContent {
        let binding = spec.fieldBinding ?? defaultFieldBinding(for: spec.blockType)

        switch binding {
        case "title":
            return .text(document.title)
        case "overview", "summary":
            return .text(document.summary)
        case "cue_questions":
            return .list(document.cueQuestions)
        case "key_points":
            return .list(document.keyPoints)
        case "sections", "context", "recommendation", "decisions":
            return .sections(document.sections)
        case "callouts":
            return .callouts(document.callouts.filter { $0.kind != .warning })
        case "warnings":
            return .callouts(document.callouts.filter { $0.kind == .warning })
        case "glossary":
            return .glossary(document.glossary)
        case "study_cards":
            return .studyCards(document.studyCards)
        case "review_questions":
            return .list(document.reviewQuestions)
        case "action_items":
            return .list(document.actionItems)
        case "summary_boxes":
            return .boxes(templateBoxes(for: .summary, document: document))
        case "key_boxes":
            return .boxes(templateBoxes(for: .key, document: document))
        case "warning_boxes":
            return .boxes(templateBoxes(for: .warning, document: document))
        case "code_boxes":
            return .boxes(templateBoxes(for: .code, document: document))
        case "result_boxes":
            return .boxes(templateBoxes(for: .result, document: document))
        case "exam_boxes":
            return .boxes(templateBoxes(for: .exam, document: document))
        case "explanation_boxes":
            return .boxes(templateBoxes(for: .explanation, document: document))
        case "example_boxes":
            return .boxes(templateBoxes(for: .example, document: document))
        default:
            return .list([])
        }
    }

    private static func templateBoxes(
        for kind: StructuredTemplateBoxKind,
        document: StructuredDocument
    ) -> [StructuredTemplateBox] {
        let explicitBoxes = document.templateBoxes
            .filter { $0.kind == kind }
            .map { box in
                StructuredTemplateBox(
                    kind: box.kind,
                    title: box.title.trimmed,
                    body: box.body.trimmed,
                    items: box.items.map(\.trimmed).filter { !$0.isEmpty }
                )
            }
            .filter { !$0.title.isEmpty || !$0.body.isEmpty || !$0.items.isEmpty }

        if !explicitBoxes.isEmpty {
            return explicitBoxes
        }

        switch kind {
        case .summary:
            let summary = document.summary.trimmed
            guard !summary.isEmpty else { return [] }
            return [StructuredTemplateBox(kind: .summary, title: "Summary", body: summary)]
        case .key:
            let items = document.keyPoints.map(\.trimmed).filter { !$0.isEmpty }
            guard !items.isEmpty else { return [] }
            return [StructuredTemplateBox(kind: .key, title: "Key Points", body: "", items: items)]
        case .warning:
            return document.callouts
                .filter { $0.kind == .warning }
                .map { StructuredTemplateBox(kind: .warning, title: $0.title.trimmed, body: $0.body.trimmed) }
                .filter { !$0.title.isEmpty || !$0.body.isEmpty }
        case .code:
            return []
        case .result:
            let items = document.actionItems.map(\.trimmed).filter { !$0.isEmpty }
            guard !items.isEmpty else { return [] }
            return [StructuredTemplateBox(kind: .result, title: "Result", body: "", items: items)]
        case .exam:
            let items = document.reviewQuestions.map(\.trimmed).filter { !$0.isEmpty }
            guard !items.isEmpty else { return [] }
            return [StructuredTemplateBox(kind: .exam, title: "Review Questions", body: "", items: items)]
        case .explanation:
            return document.callouts
                .filter { $0.kind == .note }
                .map { StructuredTemplateBox(kind: .explanation, title: $0.title.trimmed, body: $0.body.trimmed) }
                .filter { !$0.title.isEmpty || !$0.body.isEmpty }
        case .example:
            return document.callouts
                .filter { $0.kind == .example }
                .map { StructuredTemplateBox(kind: .example, title: $0.title.trimmed, body: $0.body.trimmed) }
                .filter { !$0.title.isEmpty || !$0.body.isEmpty }
        }
    }

    private static func defaultFieldBinding(for blockType: TemplateBlockType) -> String {
        switch blockType {
        case .title:
            return "title"
        case .summary:
            return "overview"
        case .section:
            return "sections"
        case .keyPoints:
            return "key_points"
        case .cueQuestions:
            return "cue_questions"
        case .callouts:
            return "callouts"
        case .glossary:
            return "glossary"
        case .studyCards:
            return "study_cards"
        case .reviewQuestions, .exercise:
            return "review_questions"
        case .actionItems:
            return "action_items"
        case .warningBox:
            return "warnings"
        }
    }
}

enum TemplatePackMarkdownEmitter {
    static func emit(_ rendered: RenderedTemplateDocument) -> String {
        var lines: [String] = ["# \(rendered.title)"]

        for block in rendered.blocks {
            switch block.blockType {
            case .summary:
                if let placeholder = block.placeholderText {
                    lines.append("")
                    lines.append("> \(placeholder)")
                } else if let body = block.body?.trimmed, !body.isEmpty {
                    lines.append("")
                    lines.append(body)
                }
            case .section:
                lines.append("")
                lines.append("## \(block.title)")
                if let body = block.body?.trimmed, !body.isEmpty {
                    lines.append(body)
                }
                if !block.items.isEmpty {
                    lines.append(contentsOf: block.items.map { "- \($0)" })
                }
                if let placeholder = block.placeholderText {
                    lines.append("> \(placeholder)")
                }
            case .callouts:
                lines.append("")
                lines.append("### \(block.title)")
                if let body = block.body?.trimmed, !body.isEmpty {
                    lines.append(body)
                }
                if let placeholder = block.placeholderText {
                    lines.append("> \(placeholder)")
                }
            default:
                lines.append("")
                lines.append("## \(block.title)")
                if let body = block.body?.trimmed, !body.isEmpty {
                    lines.append(body)
                }
                if !block.items.isEmpty {
                    lines.append(contentsOf: block.items.map { "- \($0)" })
                }
                if let placeholder = block.placeholderText {
                    lines.append("> \(placeholder)")
                }
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func emit(document: StructuredDocument, pack: TemplatePack, surface: RenderSurface) throws -> String {
        emit(try TemplatePackRenderer.render(document: document, pack: pack, surface: surface))
    }
}

extension DraftVersion {
    func resolvedTemplatePackForRendering() throws -> TemplatePack {
        if let storedPackData = structuredDoc.exportMetadata.contentTemplatePackData,
           let storedPack = try? JSONDecoder().decode(TemplatePack.self, from: storedPackData) {
            var themedStoredPack = storedPack
            if storedPack.behavior.followsVisualTheme {
                themedStoredPack.style = TemplatePackDefaults.semanticThemedStyle(
                    theme: DocumentTheme.named(structuredDoc.exportMetadata.visualTemplateName),
                    preserving: storedPack.style
                )
            }
            return themedStoredPack
        }

        let basePack = try Template.builtinContentTemplate(
            named: structuredDoc.exportMetadata.contentTemplateName,
            goalType: goalType
        )?.templatePack() ?? TemplatePackDefaults.pack(
            for: goalType.templateArchetype,
            named: structuredDoc.exportMetadata.contentTemplateName
        )

        var themedPack = basePack
        themedPack.style = TemplatePackDefaults.semanticThemedStyle(
            theme: DocumentTheme.named(structuredDoc.exportMetadata.visualTemplateName),
            preserving: basePack.style
        )
        return themedPack
    }

    func renderedTemplateDocument(for surface: RenderSurface) throws -> RenderedTemplateDocument {
        try TemplatePackRenderer.render(
            document: structuredDoc,
            pack: resolvedTemplatePackForRendering(),
            surface: surface
        )
    }

    func renderedMarkdown(for surface: RenderSurface) throws -> String {
        try TemplatePackMarkdownEmitter.emit(document: structuredDoc, pack: resolvedTemplatePackForRendering(), surface: surface)
    }
}

private enum RenderedTemplateContent {
    case text(String)
    case list([String])
    case sections([StructuredSection])
    case callouts([StructuredCallout])
    case boxes([StructuredTemplateBox])
    case glossary([GlossaryItem])
    case studyCards([StudyCard])
}

private extension SurfaceEmptyBehavior {
    func behavior(for surface: RenderSurface) -> EmptyBlockBehavior {
        switch surface {
        case .authoring:
            return authoring
        case .preview:
            return preview
        case .export:
            return export
        }
    }
}

private extension GoalType {
    var templateArchetype: TemplateArchetype {
        switch self {
        case .actionItems:
            return .meetingBrief
        case .formalDocument:
            return .formalBrief
        case .summary, .structuredNotes:
            return .technicalNote
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
