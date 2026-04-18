import Foundation

struct DecodedLatexTemplatePackSource: Sendable {
    var pack: TemplatePack
    var goalType: GoalType
}

enum TemplatePackLatexCodec {
    private static let directivePrefix = "% notescurator."

    static func emit(template: Template, pack: TemplatePack) -> String {
        var lines: [String] = [
            "% NotesCurator LaTeX Template v1",
            "% Edit the notescurator metadata comments to change the saved template structure.",
            "% notescurator.name: \(template.name)",
            "% notescurator.subtitle: \(template.subtitle)",
            "% notescurator.description: \(template.templateDescription)",
            "% notescurator.goal: \(template.configuredGoalType.rawValue)",
            "% notescurator.archetype: \(pack.archetype.rawValue)",
            "% notescurator.behavior: \(jsonLine(pack.behavior))",
            "% notescurator.color.accent: \(pack.style.accentHex)",
            "% notescurator.color.surface: \(pack.style.surfaceHex)",
            "% notescurator.color.border: \(pack.style.borderHex)",
            "% notescurator.color.secondary: \(pack.style.secondaryHex)",
        ]

        pack.schema.fields.forEach {
            lines.append("% notescurator.field: \(jsonLine($0))")
        }
        pack.style.boxStyles.forEach {
            lines.append("% notescurator.box_style: \(jsonLine($0))")
        }
        pack.layout.blocks.forEach {
            lines.append("% notescurator.block: \(jsonLine($0))")
        }
        if let importedPreview = pack.importedPreview {
            lines.append("% notescurator.imported_preview: \(jsonLine(importedPreview))")
        }

        lines.append("")
        lines.append("\\documentclass{article}")
        lines.append("\\usepackage[margin=1in]{geometry}")
        lines.append("\\usepackage{xcolor}")
        lines.append("\\usepackage[most]{tcolorbox}")
        lines.append("\\usepackage{enumitem}")
        lines.append("")
        lines.append("\\definecolor{TemplateAccent}{HTML}{\(templateHex(pack.style.accentHex))}")
        lines.append("\\definecolor{TemplateSurface}{HTML}{\(templateHex(pack.style.surfaceHex))}")
        lines.append("\\definecolor{TemplateBorder}{HTML}{\(templateHex(pack.style.borderHex))}")
        lines.append("\\definecolor{TemplateSecondary}{HTML}{\(templateHex(pack.style.secondaryHex))}")
        lines.append("")

        let boxStyles = emittedBoxStyles(for: pack)
        boxStyles.forEach { style in
            lines.append("\\definecolor{\(boxColorName(for: style.variant, role: "Frame"))}{HTML}{\(templateHex(style.borderHex))}")
            lines.append("\\definecolor{\(boxColorName(for: style.variant, role: "Background"))}{HTML}{\(templateHex(style.backgroundHex))}")
            lines.append("\\definecolor{\(boxColorName(for: style.variant, role: "Title"))}{HTML}{\(templateHex(style.titleBackgroundHex ?? style.borderHex))}")
            lines.append("\\definecolor{\(boxColorName(for: style.variant, role: "TitleText"))}{HTML}{\(templateHex(style.titleTextHex))}")
        }
        if !boxStyles.isEmpty {
            lines.append("")
        }
        boxStyles.forEach { style in
            lines.append(newTColorBoxLine(for: style))
        }

        lines.append("")
        lines.append("\\begin{document}")
        lines.append("{\\Huge\\bfseries\\color{TemplateAccent} \(latexEscaped(template.name))}\\\\[-2pt]")
        if !template.subtitle.trimmed.isEmpty {
            lines.append("{\\large\\color{TemplateSecondary} \(latexEscaped(template.subtitle))}\\\\[8pt]")
        } else {
            lines.append("\\vspace{8pt}")
        }
        if !template.templateDescription.trimmed.isEmpty {
            lines.append("% \(template.templateDescription)")
        }
        lines.append("\\hrule height 0.9pt")

        for block in pack.layout.blocks {
            lines.append("")
            lines.append(contentsOf: latexSnippet(for: block))
        }

        lines.append("\\end{document}")
        return lines.joined(separator: "\n")
    }

    static func decode(source: String, fallbackGoal: GoalType) throws -> DecodedLatexTemplatePackSource {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        if let decoded = try decodeDirectiveBackedTemplate(from: normalized, fallbackGoal: fallbackGoal) {
            return decoded
        }

        let review = try LatexTemplateImporter.importTemplate(from: normalized)
        return DecodedLatexTemplatePackSource(
            pack: review.templatePack,
            goalType: legacyGoalType(for: review.templatePack.archetype)
        )
    }

    private static func decodeDirectiveBackedTemplate(
        from source: String,
        fallbackGoal: GoalType
    ) throws -> DecodedLatexTemplatePackSource? {
        var sawDirective = false
        var goalType = fallbackGoal
        var archetype: TemplateArchetype?
        var name = ""
        var subtitle = ""
        var description = ""
        var behavior = TemplateBehaviorRules()
        var accentHex = StyleKit(accentHex: "#2E5AAC").accentHex
        var surfaceHex = StyleKit(accentHex: "#2E5AAC").surfaceHex
        var borderHex = StyleKit(accentHex: "#2E5AAC").borderHex
        var secondaryHex = StyleKit(accentHex: "#2E5AAC").secondaryHex
        var fields: [RecommendedField] = []
        var blocks: [TemplateBlockSpec] = []
        var boxStyles: [TemplateBoxStyle] = []
        var importedPreview: ImportedTemplatePreview?

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(directivePrefix) else { continue }
            sawDirective = true

            if let value = directiveValue(in: line, key: "name") {
                name = value
            } else if let value = directiveValue(in: line, key: "subtitle") {
                subtitle = value
            } else if let value = directiveValue(in: line, key: "description") {
                description = value
            } else if let value = directiveValue(in: line, key: "goal"), let parsed = GoalType(rawValue: value) {
                goalType = parsed
            } else if let value = directiveValue(in: line, key: "archetype"), let parsed = TemplateArchetype(rawValue: value) {
                archetype = parsed
            } else if let value = directiveValue(in: line, key: "behavior") {
                behavior = try decodeJSONLine(value, as: TemplateBehaviorRules.self)
            } else if let value = directiveValue(in: line, key: "color.accent") {
                accentHex = value
            } else if let value = directiveValue(in: line, key: "color.surface") {
                surfaceHex = value
            } else if let value = directiveValue(in: line, key: "color.border") {
                borderHex = value
            } else if let value = directiveValue(in: line, key: "color.secondary") {
                secondaryHex = value
            } else if let value = directiveValue(in: line, key: "field") {
                fields.append(try decodeJSONLine(value, as: RecommendedField.self))
            } else if let value = directiveValue(in: line, key: "block") {
                blocks.append(try decodeJSONLine(value, as: TemplateBlockSpec.self))
            } else if let value = directiveValue(in: line, key: "box_style") {
                boxStyles.append(try decodeJSONLine(value, as: TemplateBoxStyle.self))
            } else if let value = directiveValue(in: line, key: "imported_preview") {
                importedPreview = try decodeJSONLine(value, as: ImportedTemplatePreview.self)
            }
        }

        guard sawDirective else { return nil }
        guard let archetype else {
            throw LatexTemplateImportError.unsupportedSource("Missing notescurator archetype metadata.")
        }
        guard !blocks.isEmpty else {
            throw LatexTemplateImportError.unsupportedSource("Missing notescurator block metadata.")
        }

        let pack = TemplatePack(
            identity: TemplatePackIdentity(name: name, description: subtitle.isEmpty ? description : subtitle),
            archetype: archetype,
            schema: RecommendedSchema(fields: fields),
            layout: LayoutSpec(blocks: blocks),
            style: StyleKit(
                accentHex: accentHex,
                surfaceHex: surfaceHex,
                borderHex: borderHex,
                secondaryHex: secondaryHex,
                boxStyles: boxStyles
            ),
            behavior: behavior,
            importedPreview: importedPreview
        )

        return DecodedLatexTemplatePackSource(pack: pack, goalType: goalType)
    }

    private static func directiveValue(in line: String, key: String) -> String? {
        let prefix = "\(directivePrefix)\(key):"
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func decodeJSONLine<T: Decodable>(_ value: String, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        guard let data = value.data(using: .utf8) else {
            throw LatexTemplateImportError.unsupportedSource("Invalid notescurator metadata encoding.")
        }
        return try decoder.decode(type, from: data)
    }

    private static func jsonLine<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func templateHex(_ hex: String) -> String {
        hex.replacingOccurrences(of: "#", with: "").uppercased()
    }

    private static func emittedBoxStyles(for pack: TemplatePack) -> [TemplateBoxStyle] {
        let explicit = Dictionary(uniqueKeysWithValues: pack.style.boxStyles.map { ($0.variant, $0) })
        let usedVariants = Set(pack.layout.blocks.compactMap { resolvedVariant(for: $0) })
            .subtracting([.standard])

        return usedVariants.sorted { $0.rawValue < $1.rawValue }.map { variant in
            explicit[variant] ?? defaultBoxStyle(for: variant, style: pack.style)
        }
    }

    private static func resolvedVariant(for block: TemplateBlockSpec) -> TemplateBlockStyleVariant? {
        if let parsed = TemplateBlockStyleVariant(rawValue: block.styleVariant) {
            return parsed
        }
        if let binding = block.fieldBinding, binding.hasSuffix("_boxes") {
            switch binding {
            case "summary_boxes": return .summary
            case "key_boxes": return .key
            case "meta_boxes": return .standard
            case "warning_boxes": return .warning
            case "exam_boxes", "question_boxes": return .exam
            case "checklist_boxes", "result_boxes": return .result
            case "code_boxes": return .code
            default: return .summary
            }
        }
        return nil
    }

    private static func defaultBoxStyle(for variant: TemplateBlockStyleVariant, style: StyleKit) -> TemplateBoxStyle {
        switch variant {
        case .summary:
            return TemplateBoxStyle(
                variant: .summary,
                borderHex: style.accentHex,
                backgroundHex: style.surfaceHex,
                titleBackgroundHex: style.surfaceHex,
                titleTextHex: style.accentHex,
                bodyTextHex: "#22304A"
            )
        case .key:
            return TemplateBoxStyle(
                variant: .key,
                borderHex: style.accentHex,
                backgroundHex: style.surfaceHex,
                titleBackgroundHex: style.accentHex,
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#22304A"
            )
        case .warning:
            return TemplateBoxStyle(
                variant: .warning,
                borderHex: "#C95A4A",
                backgroundHex: "#FFF7F4",
                titleBackgroundHex: "#C95A4A",
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#5A2A21"
            )
        case .exam:
            return TemplateBoxStyle(
                variant: .exam,
                borderHex: "#6D5BD0",
                backgroundHex: "#F7F5FF",
                titleBackgroundHex: "#6D5BD0",
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#2C225A"
            )
        case .code:
            return TemplateBoxStyle(
                variant: .code,
                borderHex: "#202733",
                backgroundHex: "#F4F6FA",
                titleBackgroundHex: "#202733",
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#202733"
            )
        case .result:
            return TemplateBoxStyle(
                variant: .result,
                borderHex: "#2F6A57",
                backgroundHex: "#F4FBF8",
                titleBackgroundHex: "#2F6A57",
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#1F4034"
            )
        case .standard:
            return TemplateBoxStyle(variant: .standard, borderHex: style.borderHex, backgroundHex: style.surfaceHex)
        }
    }

    private static func newTColorBoxLine(for style: TemplateBoxStyle) -> String {
        "\\newtcolorbox{\(boxEnvironmentName(for: style.variant))}[1]{colback=\(boxColorName(for: style.variant, role: "Background")),colframe=\(boxColorName(for: style.variant, role: "Frame")),coltitle=\(boxColorName(for: style.variant, role: "TitleText")),fonttitle=\\bfseries,colbacktitle=\(boxColorName(for: style.variant, role: "Title")),title={#1}}"
    }

    private static func boxEnvironmentName(for variant: TemplateBlockStyleVariant) -> String {
        switch variant {
        case .summary: return "SummaryBox"
        case .key: return "KeyBox"
        case .warning: return "WarningBox"
        case .exam: return "ExamBox"
        case .code: return "CodeBox"
        case .result: return "ResultBox"
        case .standard: return "StandardBox"
        }
    }

    private static func latexSnippet(for block: TemplateBlockSpec) -> [String] {
        let title = block.titleOverride?.trimmed.nonEmpty ?? defaultTitle(for: block.blockType)
        let binding = block.fieldBinding?.trimmed.nonEmpty ?? defaultFieldBinding(for: block.blockType)
        let variant = resolvedVariant(for: block)

        if let variant, variant != .standard, block.blockType != .section {
            return [
                "% block: \(block.blockType.rawValue) / binding=\(binding)",
                "\\begin{\(boxEnvironmentName(for: variant))}{\(latexEscaped(title))}",
                blockPlaceholder(for: block.blockType, binding: binding),
                "\\end{\(boxEnvironmentName(for: variant))}",
            ]
        }

        switch block.blockType {
        case .summary:
            return [
                "% block: summary / binding=\(binding)",
                "\\section*{\(latexEscaped(title))}",
                blockPlaceholder(for: block.blockType, binding: binding),
            ]
        case .section:
            return [
                "% block: section / binding=\(binding)",
                "\\section{\(latexEscaped(title))}",
                "{{sections.body}}",
            ]
        case .callouts, .warningBox:
            return [
                "% block: \(block.blockType.rawValue) / binding=\(binding)",
                "\\subsection*{\(latexEscaped(title))}",
                blockPlaceholder(for: block.blockType, binding: binding),
            ]
        default:
            return [
                "% block: \(block.blockType.rawValue) / binding=\(binding)",
                "\\section*{\(latexEscaped(title))}",
                "\\begin{itemize}[leftmargin=1.4em]",
                "\\item \(blockPlaceholder(for: block.blockType, binding: binding))",
                "\\end{itemize}",
            ]
        }
    }

    private static func blockPlaceholder(for blockType: TemplateBlockType, binding: String) -> String {
        switch blockType {
        case .summary:
            return "{{\(binding)}}"
        case .section:
            return "{{sections.body}}"
        case .glossary:
            return "\\textbf{{glossary.term}}: {{glossary.definition}}"
        case .studyCards:
            return "Q: {{study_cards.question}}\\\\ A: {{study_cards.answer}}"
        case .callouts, .warningBox:
            return "{{\(binding).body}}"
        default:
            return "{{\(binding)}}"
        }
    }

    private static func defaultTitle(for blockType: TemplateBlockType) -> String {
        switch blockType {
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

    private static func latexEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\textbackslash{}")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "&", with: "\\&")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func legacyGoalType(for archetype: TemplateArchetype) -> GoalType {
        switch archetype {
        case .meetingBrief:
            return .actionItems
        case .formalBrief:
            return .formalDocument
        case .technicalNote:
            return .structuredNotes
        }
    }

    private static func boxColorName(for variant: TemplateBlockStyleVariant, role: String) -> String {
        "\(boxEnvironmentName(for: variant))\(role)"
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        let trimmed = trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}
