import Foundation

enum TemplatePackDefaults {
    static func pack(
        for archetype: TemplateArchetype,
        named name: String,
        description: String = "",
        style: StyleKit? = nil
    ) -> TemplatePack {
        switch archetype {
        case .technicalNote:
            return technicalNotePack(named: name, description: description, style: style ?? .technicalNoteDefault)
        case .meetingBrief:
            return meetingBriefPack(named: name, description: description, style: style ?? .meetingBriefDefault)
        case .formalBrief:
            return formalBriefPack(named: name, description: description, style: style ?? .formalBriefDefault)
        }
    }

    static func technicalNotePack(
        named name: String,
        description: String = "",
        style: StyleKit = .technicalNoteDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .technicalNote,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "overview", label: "Overview", requiredLevel: .coreRequired),
                RecommendedField(key: "cue_questions", label: "Cue Questions", requiredLevel: .preferredOptional),
                RecommendedField(key: "key_points", label: "Key Points", requiredLevel: .coreRequired),
                RecommendedField(key: "sections", label: "Sections", requiredLevel: .templateRequired),
                RecommendedField(key: "callouts", label: "Callouts", requiredLevel: .preferredOptional),
                RecommendedField(key: "warnings", label: "Warnings", requiredLevel: .preferredOptional),
                RecommendedField(key: "glossary", label: "Glossary", requiredLevel: .preferredOptional),
                RecommendedField(key: "study_cards", label: "Study Cards", requiredLevel: .preferredOptional),
                RecommendedField(key: "review_questions", label: "Review Questions", requiredLevel: .preferredOptional),
                RecommendedField(key: "action_items", label: "Action Items", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .summary, fieldBinding: "overview", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .cueQuestions, fieldBinding: "cue_questions", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_points", styleVariant: TemplateBlockStyleVariant.key.rawValue),
                TemplateBlockSpec(blockType: .warningBox, fieldBinding: "warnings", styleVariant: TemplateBlockStyleVariant.warning.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", styleVariant: TemplateBlockStyleVariant.standard.rawValue),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "callouts", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .glossary, fieldBinding: "glossary", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .studyCards, fieldBinding: "study_cards", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .reviewQuestions, fieldBinding: "review_questions", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "action_items", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules()
        )
    }

    static func meetingBriefPack(
        named name: String,
        description: String = "",
        style: StyleKit = .meetingBriefDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .meetingBrief,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "overview", label: "Overview", requiredLevel: .coreRequired),
                RecommendedField(key: "key_points", label: "Key Points", requiredLevel: .preferredOptional),
                RecommendedField(key: "sections", label: "Sections", requiredLevel: .templateRequired),
                RecommendedField(key: "callouts", label: "Callouts", requiredLevel: .preferredOptional),
                RecommendedField(key: "action_items", label: "Action Items", requiredLevel: .coreRequired),
                RecommendedField(key: "review_questions", label: "Review Questions", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .summary, fieldBinding: "overview", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "action_items", styleVariant: TemplateBlockStyleVariant.result.rawValue),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_points", styleVariant: TemplateBlockStyleVariant.key.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", styleVariant: TemplateBlockStyleVariant.standard.rawValue),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "callouts", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .reviewQuestions, fieldBinding: "review_questions", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules()
        )
    }

    static func formalBriefPack(
        named name: String,
        description: String = "",
        style: StyleKit = .formalBriefDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .formalBrief,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "overview", label: "Overview", requiredLevel: .coreRequired),
                RecommendedField(key: "cue_questions", label: "Cue Questions", requiredLevel: .preferredOptional),
                RecommendedField(key: "key_points", label: "Key Points", requiredLevel: .preferredOptional),
                RecommendedField(key: "sections", label: "Sections", requiredLevel: .templateRequired),
                RecommendedField(key: "callouts", label: "Callouts", requiredLevel: .preferredOptional),
                RecommendedField(key: "glossary", label: "Glossary", requiredLevel: .preferredOptional),
                RecommendedField(key: "study_cards", label: "Study Cards", requiredLevel: .preferredOptional),
                RecommendedField(key: "review_questions", label: "Review Questions", requiredLevel: .preferredOptional),
                RecommendedField(key: "action_items", label: "Action Items", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .summary, fieldBinding: "overview", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .cueQuestions, fieldBinding: "cue_questions", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_points", styleVariant: TemplateBlockStyleVariant.key.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", styleVariant: TemplateBlockStyleVariant.standard.rawValue),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "callouts", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .glossary, fieldBinding: "glossary", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .studyCards, fieldBinding: "study_cards", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .reviewQuestions, fieldBinding: "review_questions", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "action_items", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules()
        )
    }

    static func importedPack(
        archetype: TemplateArchetype,
        fingerprint: SourceFingerprint,
        suggestedName: String
    ) -> TemplatePack {
        var pack = pack(
            for: archetype,
            named: suggestedName,
            description: "Imported from LaTeX"
        )
        let importedLayout = importedLayout(from: fingerprint)
        if !importedLayout.blocks.isEmpty {
            pack.layout = importedLayout
            pack.schema = importedSchema(for: importedLayout)
        }

        pack.style = StyleKit(
            accentHex: fingerprint.palette.accentHex,
            surfaceHex: fingerprint.palette.surfaceHex ?? pack.style.surfaceHex,
            borderHex: pack.style.borderHex,
            secondaryHex: pack.style.secondaryHex,
            boxStyles: pack.style.boxStyles
        )

        // Imported templates should behave like the source layout:
        // if a box has matching content we render it, otherwise we omit it.
        pack.layout.blocks = pack.layout.blocks.map { block in
            var copy = block
            copy.emptyBehavior = .hidden
            return copy
        }

        return pack
    }
}

private extension TemplatePackDefaults {
    static func importedLayout(from fingerprint: SourceFingerprint) -> LayoutSpec {
        var blocks: [TemplateBlockSpec] = []
        var seenBindings: Set<String> = []

        for boxStyle in fingerprint.boxStyles {
            guard let block = importedBlock(for: boxStyle),
                  let binding = block.fieldBinding,
                  seenBindings.insert(binding).inserted else {
                continue
            }
            blocks.append(block)
        }

        if seenBindings.insert("sections").inserted {
            blocks.append(
                TemplateBlockSpec(
                    blockType: .section,
                    fieldBinding: "sections",
                    titleOverride: "Sections",
                    styleVariant: TemplateBlockStyleVariant.standard.rawValue,
                    emptyBehavior: .hidden
                )
            )
        }

        return LayoutSpec(blocks: blocks)
    }

    static func importedSchema(for layout: LayoutSpec) -> RecommendedSchema {
        RecommendedSchema(
            fields: layout.blocks.compactMap { block in
                guard let binding = block.fieldBinding else { return nil }
                return RecommendedField(
                    key: binding,
                    label: importedFieldLabel(for: binding),
                    requiredLevel: importedFieldRequirement(for: binding)
                )
            }
        )
    }

    static func importedBlock(for style: LatexBoxStyle) -> TemplateBlockSpec? {
        guard let mapping = importedBoxMapping(for: style) else { return nil }
        return TemplateBlockSpec(
            blockType: mapping.blockType,
            fieldBinding: mapping.binding,
            titleOverride: preferredImportedTitle(for: style),
            styleVariant: mapping.variant.rawValue,
            emptyBehavior: .hidden
        )
    }

    static func importedBoxMapping(
        for style: LatexBoxStyle
    ) -> (binding: String, blockType: TemplateBlockType, variant: TemplateBlockStyleVariant)? {
        let combined = "\(style.name) \(style.title ?? "")"
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        if combined.contains("warning") || combined.contains("caution") || combined.contains("pitfall") {
            return ("warning_boxes", .warningBox, .warning)
        }
        if combined.contains("result") || combined.contains("checklist") || combined.contains("prerequisite") || combined.contains("success") {
            return ("result_boxes", .actionItems, .result)
        }
        if combined.contains("code") || combined.contains("command") || combined.contains("snippet") || combined.contains("query") || combined.contains("ascii") || combined.contains("config") {
            return ("code_boxes", .callouts, .code)
        }
        if combined.contains("exam") || combined.contains("exercise") || combined.contains("quiz") || combined.contains("q&a") || combined.contains("qa") || combined.contains("interview") || combined.contains("self check") || combined.contains("self-check") {
            return ("exam_boxes", .exercise, .exam)
        }
        if combined.contains("explanation") || combined.contains("explainer") || combined.contains("note") {
            return ("explanation_boxes", .callouts, .summary)
        }
        if combined.contains("example") || combined.contains("scenario") || combined.contains("case study") {
            return ("example_boxes", .callouts, .standard)
        }
        if combined.contains("key") || combined.contains("takeaway") || combined.contains("highlight") || combined.contains("concept") {
            return ("key_boxes", .keyPoints, .key)
        }
        if combined.contains("summary") || combined.contains("overview") || combined.contains("recap") {
            return ("summary_boxes", .summary, .summary)
        }
        return nil
    }

    static func preferredImportedTitle(for style: LatexBoxStyle) -> String {
        if let explicitTitle = style.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitTitle.isEmpty,
           explicitTitle.contains("#") == false,
           explicitTitle.contains("\\") == false {
            return explicitTitle
        }

        var rawName = style.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawName.hasSuffix("Box") {
            rawName.removeLast(3)
        }

        let withSpaces = rawName.unicodeScalars.reduce(into: "") { partial, scalar in
            let character = Character(scalar)
            if character.isUppercase, !partial.isEmpty, partial.last?.isWhitespace == false {
                partial.append(" ")
            }
            partial.append(character)
        }

        let title = withSpaces.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? style.name : title
    }

    static func importedFieldLabel(for binding: String) -> String {
        switch binding {
        case "summary_boxes":
            return "Summary Boxes"
        case "key_boxes":
            return "Key Boxes"
        case "warning_boxes":
            return "Warning Boxes"
        case "code_boxes":
            return "Code Boxes"
        case "result_boxes":
            return "Result Boxes"
        case "exam_boxes":
            return "Exam Boxes"
        case "explanation_boxes":
            return "Explanation Boxes"
        case "example_boxes":
            return "Example Boxes"
        case "sections":
            return "Sections"
        default:
            return binding
        }
    }

    static func importedFieldRequirement(for binding: String) -> TemplateFieldRequiredLevel {
        switch binding {
        case "summary_boxes":
            return .coreRequired
        case "sections":
            return .templateRequired
        default:
            return .preferredOptional
        }
    }
}

private extension StyleKit {
    static let technicalNoteDefault = StyleKit(
        accentHex: "#2E5AAC",
        surfaceHex: "#F6F9FF",
        borderHex: "#D6E2FF",
        secondaryHex: "#5B6F9A",
        boxStyles: defaultBoxStyles(
            accentHex: "#2E5AAC",
            surfaceHex: "#F6F9FF",
            borderHex: "#D6E2FF",
            secondaryHex: "#5B6F9A"
        )
    )

    static let meetingBriefDefault = StyleKit(
        accentHex: "#2F6A57",
        surfaceHex: "#F4FBF7",
        borderHex: "#D2E9DD",
        secondaryHex: "#5C7A70",
        boxStyles: defaultBoxStyles(
            accentHex: "#2F6A57",
            surfaceHex: "#F4FBF7",
            borderHex: "#D2E9DD",
            secondaryHex: "#5C7A70"
        )
    )

    static let formalBriefDefault = StyleKit(
        accentHex: "#7A5C2E",
        surfaceHex: "#FFFCF7",
        borderHex: "#E8D9BD",
        secondaryHex: "#8B7756",
        boxStyles: defaultBoxStyles(
            accentHex: "#7A5C2E",
            surfaceHex: "#FFFCF7",
            borderHex: "#E8D9BD",
            secondaryHex: "#8B7756"
        )
    )

    static func defaultBoxStyles(
        accentHex: String,
        surfaceHex: String,
        borderHex: String,
        secondaryHex: String
    ) -> [TemplateBoxStyle] {
        [
            TemplateBoxStyle(
                variant: .standard,
                borderHex: borderHex,
                backgroundHex: "#FFFFFF",
                titleTextHex: accentHex,
                bodyTextHex: "#22304A"
            ),
            TemplateBoxStyle(
                variant: .summary,
                borderHex: borderHex,
                backgroundHex: surfaceHex,
                titleBackgroundHex: borderHex,
                titleTextHex: accentHex,
                bodyTextHex: "#22304A"
            ),
            TemplateBoxStyle(
                variant: .key,
                borderHex: accentHex,
                backgroundHex: surfaceHex,
                titleBackgroundHex: accentHex,
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#22304A"
            ),
            TemplateBoxStyle(
                variant: .warning,
                borderHex: "#D95C5C",
                backgroundHex: "#FFF4F2",
                titleBackgroundHex: "#F26B6B",
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#4A2A2A"
            ),
            TemplateBoxStyle(
                variant: .exam,
                borderHex: accentHex,
                backgroundHex: "#FFFFFF",
                titleBackgroundHex: "#EEF3FF",
                titleTextHex: accentHex,
                bodyTextHex: "#22304A"
            ),
            TemplateBoxStyle(
                variant: .code,
                borderHex: "#D9DEE8",
                backgroundHex: "#F7F8FB",
                titleBackgroundHex: "#EEF1F6",
                titleTextHex: secondaryHex,
                bodyTextHex: "#1E293B"
            ),
            TemplateBoxStyle(
                variant: .result,
                borderHex: "#3C8C53",
                backgroundHex: "#F4FBF5",
                titleBackgroundHex: "#E3F4E8",
                titleTextHex: "#2E6A40",
                bodyTextHex: "#1F3D2A"
            ),
        ]
    }
}
