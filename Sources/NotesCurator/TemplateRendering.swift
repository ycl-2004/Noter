import Foundation

enum MarkdownTemplateError: Error, Equatable, LocalizedError {
    case invalidFrontMatter(String)
    case unsupportedToken(String)
    case malformedDirective(String)
    case unexpectedClosingTag(String)
    case unclosedBlock(String)
    case unsupportedField(String)

    var errorDescription: String? {
        switch self {
        case let .invalidFrontMatter(message):
            return "Invalid template front matter: \(message)"
        case let .unsupportedToken(token):
            return "Unsupported template token: \(token)"
        case let .malformedDirective(directive):
            return "Malformed template directive: \(directive)"
        case let .unexpectedClosingTag(tag):
            return "Unexpected closing tag: \(tag)"
        case let .unclosedBlock(block):
            return "Unclosed template block: \(block)"
        case let .unsupportedField(field):
            return "Unsupported item field: \(field)"
        }
    }
}

struct MarkdownTemplateFrontMatter: Equatable, Sendable {
    var goal: GoalType
    var generationHint: String
    var sampleDataKey: String

    static let `default` = Self(goal: .structuredNotes, generationHint: "", sampleDataKey: "")
}

enum MarkdownTemplateBlock: String, CaseIterable, Codable, Hashable, Sendable {
    case cueQuestions
    case keyPoints
    case sections
    case glossary
    case studyCards
    case reviewQuestions
    case actionItems
}

struct MarkdownTemplate: Equatable, Sendable {
    var frontMatter: MarkdownTemplateFrontMatter
    var body: String
    var usedBlocks: Set<MarkdownTemplateBlock>

    static func parse(
        _ source: String,
        defaultGoal: GoalType = .structuredNotes,
        defaultSampleDataKey: String = ""
    ) throws -> MarkdownTemplate {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let (frontMatter, body) = try MarkdownTemplateParser.split(source: normalized, defaultGoal: defaultGoal, defaultSampleDataKey: defaultSampleDataKey)
        let nodes = try MarkdownTemplateParser.parseNodes(in: body)
        let usedBlocks = MarkdownTemplateParser.usedBlocks(in: nodes)
        return MarkdownTemplate(
            frontMatter: frontMatter,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            usedBlocks: usedBlocks
        )
    }
}

enum MarkdownTemplateRenderer {
    static func render(template: MarkdownTemplate, document: StructuredDocument) throws -> String {
        let nodes = try MarkdownTemplateParser.parseNodes(in: template.body)
        let rendered = try render(nodes: nodes, context: .root(document: document))
        return rendered
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func render(
        template: Template,
        document: StructuredDocument,
        fallbackGoal: GoalType? = nil
    ) throws -> String {
        if template.format == .markdownTemplate, !template.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = try template.markdownTemplate(fallbackGoal: fallbackGoal ?? template.configuredGoalType)
            return try render(template: parsed, document: document)
        }

        return LegacyDocumentRenderer.render(document: document)
    }

    private static func render(nodes: [MarkdownTemplateNode], context: RenderContext) throws -> String {
        var output = ""
        for node in nodes {
            switch node {
            case let .text(text):
                output += text
            case let .variable(name):
                output += try renderVariable(name, context: context)
            case let .ifBlock(block, children):
                if context.collectionItems(for: block).isEmpty == false {
                    output += try render(nodes: children, context: context)
                }
            case let .eachBlock(block, children):
                let items = context.collectionItems(for: block)
                for item in items {
                    output += try render(nodes: children, context: .item(document: context.document, block: block, item: item))
                }
            }
        }
        return output
    }

    private static func renderVariable(_ name: String, context: RenderContext) throws -> String {
        switch context {
        case let .root(document):
            switch name {
            case "title":
                return document.title
            case "summary":
                return document.summary
            default:
                throw MarkdownTemplateError.unsupportedToken(name)
            }
        case let .item(_, block, item):
            return try item.value(for: name, in: block)
        }
    }
}

enum LegacyDocumentRenderer {
    static func render(document: StructuredDocument) -> String {
        var lines = ["# \(document.title)", "", document.summary]

        appendList(title: "Cue Questions", items: document.cueQuestions, to: &lines)
        appendList(title: "Key Points", items: document.keyPoints, to: &lines)

        for section in document.sections {
            lines.append("")
            lines.append("## \(section.title)")
            lines.append(section.body)
            if !section.bulletPoints.isEmpty {
                lines.append(contentsOf: section.bulletPoints.map { "- \($0)" })
            }
        }

        if !document.glossary.isEmpty {
            lines.append("")
            lines.append("## Glossary")
            lines.append(contentsOf: document.glossary.map { "- **\($0.term)**: \($0.definition)" })
        }

        if !document.studyCards.isEmpty {
            lines.append("")
            lines.append("## Study Cards")
            lines.append(contentsOf: document.studyCards.map { "- Q: \($0.question)\n  A: \($0.answer)" })
        }

        appendList(title: "Review Questions", items: document.reviewQuestions, to: &lines)
        appendList(title: "Action Items", items: document.actionItems, to: &lines)

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendList(title: String, items: [String], to lines: inout [String]) {
        guard !items.isEmpty else { return }
        lines.append("")
        lines.append("## \(title)")
        lines.append(contentsOf: items.map { "- \($0)" })
    }
}

private enum MarkdownTemplateParser {
    static func split(
        source: String,
        defaultGoal: GoalType,
        defaultSampleDataKey: String
    ) throws -> (MarkdownTemplateFrontMatter, String) {
        guard source.hasPrefix("---\n") else {
            return (
                MarkdownTemplateFrontMatter(
                    goal: defaultGoal,
                    generationHint: "",
                    sampleDataKey: defaultSampleDataKey
                ),
                source
            )
        }

        let remainder = String(source.dropFirst(4))
        guard let delimiterRange = remainder.range(of: "\n---\n") else {
            throw MarkdownTemplateError.invalidFrontMatter("Missing closing --- fence.")
        }

        let frontMatterSource = String(remainder[..<delimiterRange.lowerBound])
        let body = String(remainder[delimiterRange.upperBound...])
        return (
            try parseFrontMatter(frontMatterSource, defaultGoal: defaultGoal, defaultSampleDataKey: defaultSampleDataKey),
            body
        )
    }

    static func parseNodes(in source: String) throws -> [MarkdownTemplateNode] {
        var cursor = source.startIndex
        return try parseNodes(in: source, cursor: &cursor, closingTag: nil)
    }

    static func usedBlocks(in nodes: [MarkdownTemplateNode]) -> Set<MarkdownTemplateBlock> {
        var blocks: Set<MarkdownTemplateBlock> = []
        for node in nodes {
            switch node {
            case .text, .variable:
                break
            case let .ifBlock(block, children), let .eachBlock(block, children):
                blocks.insert(block)
                blocks.formUnion(usedBlocks(in: children))
            }
        }
        return blocks
    }

    private static func parseFrontMatter(
        _ source: String,
        defaultGoal: GoalType,
        defaultSampleDataKey: String
    ) throws -> MarkdownTemplateFrontMatter {
        var goal = defaultGoal
        var generationHint = ""
        var sampleDataKey = defaultSampleDataKey

        let lines = source.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            index += 1
            guard !line.isEmpty else { continue }

            if line.hasPrefix("generation_hint:") {
                let value = line.dropFirst("generation_hint:".count).trimmingCharacters(in: .whitespaces)
                if value == "|" {
                    var buffer: [String] = []
                    while index < lines.count {
                        let hintLine = lines[index]
                        if hintLine.hasPrefix(" ") || hintLine.hasPrefix("\t") {
                            buffer.append(hintLine.trimmingCharacters(in: .whitespaces))
                            index += 1
                        } else if hintLine.trimmingCharacters(in: .whitespaces).isEmpty {
                            buffer.append("")
                            index += 1
                        } else {
                            break
                        }
                    }
                    generationHint = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    generationHint = value
                }
                continue
            }

            guard let colonIndex = line.firstIndex(of: ":") else {
                throw MarkdownTemplateError.invalidFrontMatter("Expected key:value pair for `\(line)`.")
            }

            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "goal":
                guard let parsedGoal = GoalType(rawValue: value) else {
                    throw MarkdownTemplateError.invalidFrontMatter("Unknown goal `\(value)`.")
                }
                goal = parsedGoal
            case "sample_data":
                sampleDataKey = value
            default:
                continue
            }
        }

        return MarkdownTemplateFrontMatter(goal: goal, generationHint: generationHint, sampleDataKey: sampleDataKey)
    }

    private static func parseNodes(
        in source: String,
        cursor: inout String.Index,
        closingTag: String?
    ) throws -> [MarkdownTemplateNode] {
        var nodes: [MarkdownTemplateNode] = []
        while cursor < source.endIndex {
            guard let openRange = source.range(of: "{{", range: cursor..<source.endIndex) else {
                if cursor < source.endIndex {
                    nodes.append(.text(String(source[cursor..<source.endIndex])))
                    cursor = source.endIndex
                }
                break
            }

            if openRange.lowerBound > cursor {
                nodes.append(.text(String(source[cursor..<openRange.lowerBound])))
            }

            guard let closeRange = source.range(of: "}}", range: openRange.upperBound..<source.endIndex) else {
                throw MarkdownTemplateError.malformedDirective(String(source[openRange.lowerBound...]))
            }

            let token = String(source[openRange.upperBound..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            cursor = closeRange.upperBound

            if token.hasPrefix("#if ") {
                let rawBlock = String(token.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let block = MarkdownTemplateBlock(rawValue: rawBlock) else {
                    throw MarkdownTemplateError.unsupportedToken(rawBlock)
                }
                let children = try parseNodes(in: source, cursor: &cursor, closingTag: "/if")
                nodes.append(.ifBlock(block, children))
                continue
            }

            if token.hasPrefix("#each ") {
                let rawBlock = String(token.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let block = MarkdownTemplateBlock(rawValue: rawBlock) else {
                    throw MarkdownTemplateError.unsupportedToken(rawBlock)
                }
                let children = try parseNodes(in: source, cursor: &cursor, closingTag: "/each")
                nodes.append(.eachBlock(block, children))
                continue
            }

            if token.hasPrefix("/") {
                if token == closingTag {
                    return nodes
                }
                throw MarkdownTemplateError.unexpectedClosingTag(token)
            }

            try validateVariable(token)
            nodes.append(.variable(token))
        }

        if let closingTag {
            throw MarkdownTemplateError.unclosedBlock(closingTag)
        }
        return nodes
    }

    private static func validateVariable(_ token: String) throws {
        let supportedRootVariables = ["title", "summary", "item", "body", "term", "definition", "question", "answer"]
        let sectionVariables = ["title"]
        if supportedRootVariables.contains(token) || sectionVariables.contains(token) || token == "bullets" {
            return
        }
        throw MarkdownTemplateError.unsupportedToken(token)
    }
}

private indirect enum MarkdownTemplateNode: Equatable {
    case text(String)
    case variable(String)
    case ifBlock(MarkdownTemplateBlock, [MarkdownTemplateNode])
    case eachBlock(MarkdownTemplateBlock, [MarkdownTemplateNode])
}

private enum RenderContext {
    case root(document: StructuredDocument)
    case item(document: StructuredDocument, block: MarkdownTemplateBlock, item: MarkdownTemplateItem)

    var document: StructuredDocument {
        switch self {
        case let .root(document), let .item(document, _, _):
            return document
        }
    }

    func collectionItems(for block: MarkdownTemplateBlock) -> [MarkdownTemplateItem] {
        switch block {
        case .cueQuestions:
            return document.cueQuestions.map(MarkdownTemplateItem.string)
        case .keyPoints:
            return document.keyPoints.map(MarkdownTemplateItem.string)
        case .sections:
            return document.sections.map(MarkdownTemplateItem.section)
        case .glossary:
            return document.glossary.map(MarkdownTemplateItem.glossary)
        case .studyCards:
            return document.studyCards.map(MarkdownTemplateItem.studyCard)
        case .reviewQuestions:
            return document.reviewQuestions.map(MarkdownTemplateItem.string)
        case .actionItems:
            return document.actionItems.map(MarkdownTemplateItem.string)
        }
    }
}

private enum MarkdownTemplateItem {
    case string(String)
    case section(StructuredSection)
    case glossary(GlossaryItem)
    case studyCard(StudyCard)

    func value(for field: String, in block: MarkdownTemplateBlock) throws -> String {
        switch (block, self, field) {
        case (_, let .string(value), "item"):
            return value
        case (.sections, let .section(section), "title"):
            return section.title
        case (.sections, let .section(section), "body"):
            return section.body
        case (.sections, let .section(section), "bullets"):
            return section.bulletPoints.map { "- \($0)" }.joined(separator: "\n")
        case (.glossary, let .glossary(item), "term"):
            return item.term
        case (.glossary, let .glossary(item), "definition"):
            return item.definition
        case (.studyCards, let .studyCard(card), "question"):
            return card.question
        case (.studyCards, let .studyCard(card), "answer"):
            return card.answer
        default:
            throw MarkdownTemplateError.unsupportedField(field)
        }
    }
}

extension Template {
    static var defaultTemplates: [Template] {
        builtinContentTemplates + builtinVisualTemplates
    }

    static var builtinContentTemplates: [Template] {
        [
            summaryTemplate,
            structuredNotesTemplate,
            lectureNotesTemplate,
            studyGuideTemplate,
            technicalDeepDiveTemplate,
            formalDocumentTemplate,
            actionItemsTemplate,
        ]
    }

    static var builtinVisualTemplates: [Template] {
        [
            Template(kind: .visual, scope: .system, name: "Oceanic Blue", subtitle: "Trustworthy and clear", templateDescription: "Cool, crisp default for daily notes and exports.", config: ["accent": "#165FCA", "surface": "#F6F9FF", "mood": "Trustworthy and clear"]),
            Template(kind: .visual, scope: .system, name: "Graphite", subtitle: "Neutral and focused", templateDescription: "Quiet grayscale framing for business and technical documents.", config: ["accent": "#2A3347", "surface": "#F7F8FB", "mood": "Neutral and focused"]),
            Template(kind: .visual, scope: .system, name: "Bloom", subtitle: "Warm and expressive", templateDescription: "A softer, more editorial presentation with warmer accents.", config: ["accent": "#D7568B", "surface": "#FFF8FB", "mood": "Warm and expressive"]),
            Template(kind: .visual, scope: .system, name: "Ivory Lecture", subtitle: "Academic and calm", templateDescription: "Warm serif-friendly framing for study-heavy material.", config: ["accent": "#7A5C2E", "surface": "#FFFCF8", "mood": "Academic and calm"]),
            Template(kind: .visual, scope: .system, name: "Sage Ledger", subtitle: "Measured and composed", templateDescription: "Grounded green theme suited to plans, briefs, and reviews.", config: ["accent": "#2F6A57", "surface": "#F8FCFA", "mood": "Measured and composed"]),
            Template(kind: .visual, scope: .system, name: "Indigo Ink", subtitle: "Modern and confident", templateDescription: "Confident blue-violet framing for denser technical notes.", config: ["accent": "#4F46E5", "surface": "#EEF2FF", "mood": "Modern and confident"]),
            Template(kind: .visual, scope: .system, name: "Emerald Grove", subtitle: "Fresh and reliable", templateDescription: "Bright green accent theme for clean handoff documents.", config: ["accent": "#047857", "surface": "#ECFDF5", "mood": "Fresh and reliable"]),
            Template(kind: .visual, scope: .system, name: "Amber Journal", subtitle: "Optimistic and editorial", templateDescription: "Warm amber theme that reads like a polished field journal.", config: ["accent": "#D97706", "surface": "#FFFBEB", "mood": "Optimistic and editorial"]),
            Template(kind: .visual, scope: .system, name: "Rose Studio", subtitle: "Energetic and creative", templateDescription: "High-energy red-pink treatment for brainstorms and creative briefs.", config: ["accent": "#E11D48", "surface": "#FFF1F2", "mood": "Energetic and creative"]),
            Template(kind: .visual, scope: .system, name: "Teal Current", subtitle: "Clean and balanced", templateDescription: "Balanced teal framing for steady, contemporary exports.", config: ["accent": "#0F766E", "surface": "#F0FDFA", "mood": "Clean and balanced"]),
        ]
    }

    static func builtinContentTemplate(named name: String, goalType: GoalType? = nil) -> Template? {
        builtinContentTemplates.first { $0.name == name } ?? fallbackBuiltinTemplate(goalType: goalType, name: name)
    }

    static func starterContentTemplate(name: String = "New Template") -> Template {
        Template(
            kind: .content,
            scope: .user,
            name: name,
            subtitle: "Custom markdown template",
            templateDescription: "Author a custom layout in the Template Library.",
            format: .markdownTemplate,
            body: structuredNotesTemplate.body,
            config: structuredNotesTemplate.config
        )
    }

    private static func fallbackBuiltinTemplate(goalType: GoalType?, name: String) -> Template? {
        switch goalType {
        case .summary:
            return summaryTemplate.renamed(to: name)
        case .formalDocument:
            return formalDocumentTemplate.renamed(to: name)
        case .actionItems:
            return actionItemsTemplate.renamed(to: name)
        case .structuredNotes, .none:
            return structuredNotesTemplate.renamed(to: name)
        }
    }

    fileprivate func renamed(to name: String) -> Template {
        var copy = self
        copy.name = name
        return copy
    }

    func markdownTemplate(fallbackGoal: GoalType? = nil) throws -> MarkdownTemplate {
        if format == .markdownTemplate, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try MarkdownTemplate.parse(
                body,
                defaultGoal: fallbackGoal ?? configuredGoalType,
                defaultSampleDataKey: defaultSampleDataKey
            )
        }

        if let builtin = Template.builtinContentTemplate(named: name, goalType: fallbackGoal ?? configuredGoalType) {
            return try MarkdownTemplate.parse(
                builtin.body,
                defaultGoal: fallbackGoal ?? builtin.configuredGoalType,
                defaultSampleDataKey: builtin.defaultSampleDataKey
            )
        }

        return try MarkdownTemplate.parse(
            Template.structuredNotesTemplate.body,
            defaultGoal: fallbackGoal ?? configuredGoalType,
            defaultSampleDataKey: defaultSampleDataKey
        )
    }

    var defaultSampleDataKey: String {
        switch configuredGoalType {
        case .actionItems:
            return "action_plan"
        case .formalDocument:
            return "formal_brief"
        case .summary, .structuredNotes:
            return "study_guide"
        }
    }

    fileprivate static let summaryTemplate = Template(
        kind: .content,
        scope: .system,
        name: "Summary",
        subtitle: "Fast condensation",
        templateDescription: "Condenses source material into the shortest still-useful briefing.",
        format: .markdownTemplate,
        body: """
        ---
        goal: summary
        generation_hint: |
          Keep the document compact and avoid over-expanding secondary sections.
        sample_data: study_guide
        ---
        # {{title}}

        {{summary}}

        {{#if keyPoints}}
        ## Essential Takeaways
        {{#each keyPoints}}
        - {{item}}
        {{/each}}
        {{/if}}

        {{#if actionItems}}
        ## Immediate Follow-up
        {{#each actionItems}}
        - {{item}}
        {{/each}}
        {{/if}}
        """,
        config: [
            "goal": GoalType.summary.rawValue,
            "purpose": "Condense a large source into the shortest useful version with only the primary ideas.",
            "completeness": "Lowest completeness; minor context and secondary detail are intentionally removed."
        ]
    )

    fileprivate static let structuredNotesTemplate = Template(
        kind: .content,
        scope: .system,
        name: "Structured Notes",
        subtitle: "Balanced recall support",
        templateDescription: "Organizes core ideas, study cues, and body sections in a balanced note format.",
        format: .markdownTemplate,
        body: """
        ---
        goal: structuredNotes
        generation_hint: |
          Balance quick recall aids with readable explanatory sections.
        sample_data: study_guide
        ---
        # {{title}}

        > {{summary}}

        {{#if cueQuestions}}
        ## Cue Questions
        {{#each cueQuestions}}
        - {{item}}
        {{/each}}
        {{/if}}

        {{#if keyPoints}}
        ## Key Points
        {{#each keyPoints}}
        - {{item}}
        {{/each}}
        {{/if}}

        {{#if sections}}
        ## Notes
        {{#each sections}}
        ### {{title}}
        {{body}}

        {{/each}}
        {{/if}}

        {{#if reviewQuestions}}
        ## Review Questions
        {{#each reviewQuestions}}
        - {{item}}
        {{/each}}
        {{/if}}
        """,
        config: [
            "goal": GoalType.structuredNotes.rawValue,
            "purpose": "Organize material for learning and recall with cues, sections, and review support.",
            "completeness": "Balanced completeness; preserves main ideas, relationships, and study aids."
        ]
    )

    fileprivate static let lectureNotesTemplate = Template(
        kind: .content,
        scope: .system,
        name: "Lecture Notes",
        subtitle: "Teaching-first structure",
        templateDescription: "Places the narrative arc and major sections first, then adds recall aids after the teaching flow.",
        format: .markdownTemplate,
        body: """
        ---
        goal: structuredNotes
        generation_hint: |
          Preserve the teaching flow and keep sections expansive enough to read top to bottom.
        sample_data: study_guide
        ---
        # {{title}}

        {{summary}}

        {{#if sections}}
        ## Lecture Flow
        {{#each sections}}
        ### {{title}}
        {{body}}

        {{/each}}
        {{/if}}

        {{#if keyPoints}}
        ## Recap
        {{#each keyPoints}}
        - {{item}}
        {{/each}}
        {{/if}}
        """,
        config: [
            "goal": GoalType.structuredNotes.rawValue,
            "style": "teaching",
            "purpose": "Preserve the lecture or lesson sequence before recall scaffolding.",
            "completeness": "Balanced completeness with a stronger narrative flow."
        ]
    )

    fileprivate static let studyGuideTemplate = Template(
        kind: .content,
        scope: .system,
        name: "Study Guide",
        subtitle: "Review-first format",
        templateDescription: "Moves cue questions, glossary, and study cards to the front so the note reads like a study pack.",
        format: .markdownTemplate,
        body: """
        ---
        goal: structuredNotes
        generation_hint: |
          Prioritize recall, terminology, and self-testing assets over long exposition.
        sample_data: study_guide
        ---
        # {{title}}

        {{summary}}

        {{#if cueQuestions}}
        ## Start Here
        {{#each cueQuestions}}
        - {{item}}
        {{/each}}
        {{/if}}

        {{#if glossary}}
        ## Glossary
        {{#each glossary}}
        - **{{term}}**: {{definition}}
        {{/each}}
        {{/if}}

        {{#if studyCards}}
        ## Study Cards
        {{#each studyCards}}
        ### {{question}}
        {{answer}}

        {{/each}}
        {{/if}}

        {{#if reviewQuestions}}
        ## Self-Check
        {{#each reviewQuestions}}
        - {{item}}
        {{/each}}
        {{/if}}
        """,
        config: [
            "goal": GoalType.structuredNotes.rawValue,
            "style": "review",
            "purpose": "Turn the material into a study-ready guide with strong recall aids.",
            "completeness": "Balanced completeness with more emphasis on testing and terminology."
        ]
    )

    fileprivate static let technicalDeepDiveTemplate = Template(
        kind: .content,
        scope: .system,
        name: "Technical Deep Dive",
        subtitle: "Dense technical walkthrough",
        templateDescription: "Keeps a compact executive summary, then expands implementation details and glossary support.",
        format: .markdownTemplate,
        body: """
        ---
        goal: formalDocument
        generation_hint: |
          Preserve technical detail and use sections to explain mechanisms, tradeoffs, and implementation notes.
        sample_data: formal_brief
        ---
        # {{title}}

        ## Executive Summary
        {{summary}}

        {{#if keyPoints}}
        ## Critical Details
        {{#each keyPoints}}
        - {{item}}
        {{/each}}
        {{/if}}

        {{#if sections}}
        ## Deep Dive
        {{#each sections}}
        ### {{title}}
        {{body}}

        {{/each}}
        {{/if}}

        {{#if glossary}}
        ## Terminology
        {{#each glossary}}
        - **{{term}}**: {{definition}}
        {{/each}}
        {{/if}}
        """,
        config: [
            "goal": GoalType.formalDocument.rawValue,
            "style": "technical",
            "purpose": "Present the material as a detailed technical walkthrough.",
            "completeness": "High completeness with strong emphasis on mechanism and terminology."
        ]
    )

    fileprivate static let formalDocumentTemplate = Template(
        kind: .content,
        scope: .system,
        name: "Formal Document",
        subtitle: "Context and recommendations",
        templateDescription: "Shapes the output like a polished memo or brief with context, findings, and recommendations.",
        format: .markdownTemplate,
        body: """
        ---
        goal: formalDocument
        generation_hint: |
          Frame the output like a polished brief for stakeholders and keep recommendations easy to find.
        sample_data: formal_brief
        ---
        # {{title}}

        ## Executive Summary
        {{summary}}

        {{#if sections}}
        ## Context
        {{#each sections}}
        ### {{title}}
        {{body}}

        {{/each}}
        {{/if}}

        {{#if actionItems}}
        ## Recommendations
        {{#each actionItems}}
        - {{item}}
        {{/each}}
        {{/if}}
        """,
        config: [
            "goal": GoalType.formalDocument.rawValue,
            "purpose": "Present the material for a defined audience as a polished brief, memo, or report.",
            "completeness": "Highest completeness; keeps fuller context, structure, explanation, and recommendations."
        ]
    )

    fileprivate static let actionItemsTemplate = Template(
        kind: .content,
        scope: .system,
        name: "Action Items",
        subtitle: "Task-first structure",
        templateDescription: "Surfaces execution work first, then preserves the supporting context underneath.",
        format: .markdownTemplate,
        body: """
        ---
        goal: actionItems
        generation_hint: |
          Lead with the next steps, owners, and deadlines before supporting detail.
        sample_data: action_plan
        ---
        # {{title}}

        > {{summary}}

        {{#if actionItems}}
        ## Next Steps
        {{#each actionItems}}
        - {{item}}
        {{/each}}
        {{/if}}

        {{#if keyPoints}}
        ## Decision Highlights
        {{#each keyPoints}}
        - {{item}}
        {{/each}}
        {{/if}}

        {{#if sections}}
        ## Supporting Context
        {{#each sections}}
        ### {{title}}
        {{body}}

        {{/each}}
        {{/if}}
        """,
        config: [
            "goal": GoalType.actionItems.rawValue,
            "purpose": "Turn discussion into trackable follow-ups with clear next steps, owners, and deadlines.",
            "completeness": "Execution-focused completeness; background detail is compressed behind what happens next."
        ]
    )
}

extension Template {
    var configuredGoalType: GoalType {
        GoalType(rawValue: config["goal"] ?? "") ?? .structuredNotes
    }
}
