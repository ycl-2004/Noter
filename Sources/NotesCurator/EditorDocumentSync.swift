import Foundation

struct EditorDocumentSync {
    static func inferredTitle(document: String, fallback: String) -> String {
        let parser = Parser(document: document, existing: nil)
        return parser.inferredTitle() ?? fallback
    }

    static func sync(
        document: String,
        into existing: StructuredDocument,
        language: OutputLanguage
    ) -> StructuredDocument {
        let parser = Parser(document: document, existing: existing, language: language)
        return parser.parse()
    }
}

private struct Parser {
    private let document: String
    private let existing: StructuredDocument?
    private let language: OutputLanguage?

    init(document: String, existing: StructuredDocument?, language: OutputLanguage? = nil) {
        self.document = document.replacingOccurrences(of: "\r\n", with: "\n")
        self.existing = existing
        self.language = language
    }

    func parse() -> StructuredDocument {
        guard let existing else {
            fatalError("Parser.parse() requires an existing structured document.")
        }
        let lines = document.components(separatedBy: .newlines)
        let resolvedTitle = inferredTitle(from: lines) ?? existing.title
        let contentLines = remainingLines(afterRemovingTitleFrom: lines)

        let parsed = parseSegments(from: contentLines)
        var updated = existing
        updated.title = resolvedTitle

        guard parsed.hasStructuredContent else {
            let paragraphs = paragraphs(from: contentLines.map(\.trimmed))
            let fallbackSummary = paragraphs.first ?? existing.summary
            let fallbackBody = paragraphs.dropFirst().joined(separator: "\n\n")
            updated.summary = fallbackSummary
            updated.cueQuestions = []
            updated.keyPoints = []
            updated.glossary = []
            updated.callouts = []
            updated.studyCards = []
            updated.actionItems = []
            updated.reviewQuestions = []
            updated.sections = fallbackBody.nonEmpty.map {
                [
                    StructuredSection(
                        title: fallbackSectionTitle(existing: existing),
                        body: $0
                    )
                ]
            } ?? []
            return updated
        }

        if let summary = parsed.summary, !summary.isEmpty {
            updated.summary = summary
        } else if !parsed.sections.isEmpty {
            updated.summary = parsed.sections[0].body.nonEmpty ?? existing.summary
        }

        updated.cueQuestions = parsed.cueQuestions
        updated.keyPoints = parsed.keyPoints
        updated.sections = parsed.sections
        updated.glossary = parsed.glossary
        updated.callouts = parsed.callouts
        updated.studyCards = parsed.studyCards
        updated.actionItems = parsed.actionItems
        updated.reviewQuestions = parsed.reviewQuestions
        return updated
    }

    func inferredTitle() -> String? {
        inferredTitle(from: document.components(separatedBy: .newlines))
    }

    private func inferredTitle(from lines: [String]) -> String? {
        for line in lines {
            let trimmed = line.trimmed
            guard !trimmed.isEmpty else { continue }
            let candidate = stripHeadingPrefix(from: trimmed)
            guard !candidate.isEmpty, headingKind(for: candidate) == nil else { continue }
            return candidate
        }
        return nil
    }

    private func remainingLines(afterRemovingTitleFrom lines: [String]) -> [String] {
        var skippedTitle = false
        return lines.filter { line in
            let trimmed = line.trimmed
            if skippedTitle || trimmed.isEmpty {
                return true
            }
            let candidate = stripHeadingPrefix(from: trimmed)
            if !candidate.isEmpty, headingKind(for: candidate) == nil {
                skippedTitle = true
                return false
            }
            return true
        }
    }

    private func firstBodyParagraph(in lines: [String]) -> String? {
        let paragraphs = paragraphs(from: lines.map(\.trimmed))
        return paragraphs.first?.nonEmpty
    }

    private func fallbackSectionTitle(existing: StructuredDocument) -> String {
        if let existingTitle = existing.sections.first?.title.nonEmpty {
            return existingTitle
        }
        return language == .chinese ? "概览" : "Overview"
    }

    private func parseSegments(from lines: [String]) -> ParsedContent {
        var result = ParsedContent()
        var currentKind: SegmentKind = .summary
        var buffer: [String] = []

        func flush() {
            let payload = SegmentPayload(lines: buffer)
            switch currentKind {
            case .summary:
                let summary = payload.bodyText.nonEmpty
                if let summary {
                    result.summary = summary
                }
            case .cueQuestions:
                result.cueQuestions = payload.items
            case .keyPoints:
                result.keyPoints = payload.items
            case .glossary:
                result.glossary = payload.glossary
            case .studyCards:
                result.studyCards = payload.studyCards
            case .actionItems:
                result.actionItems = payload.items
            case .reviewQuestions:
                result.reviewQuestions = payload.items
            case .section(let title):
                if payload.hasContent {
                    result.sections.append(
                        StructuredSection(
                            title: title,
                            body: payload.bodyText,
                            bulletPoints: payload.bullets
                        )
                    )
                }
            case .callout(let kind, let title):
                if let body = payload.bodyText.nonEmpty {
                    result.callouts.append(StructuredCallout(kind: kind, title: title, body: body))
                }
            }
            buffer.removeAll(keepingCapacity: true)
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmed
            if isHorizontalRule(trimmed) {
                continue
            }
            if let heading = parseHeading(from: trimmed) {
                flush()
                currentKind = heading
                result.hasStructuredContent = true
                continue
            }
            if let callout = parseCallout(from: trimmed) {
                flush()
                currentKind = .callout(kind: callout.kind, title: callout.title)
                result.hasStructuredContent = true
                continue
            }
            buffer.append(rawLine)
        }

        flush()
        return result
    }

    private func parseHeading(from line: String) -> SegmentKind? {
        guard !line.isEmpty else { return nil }
        let candidate = stripHeadingPrefix(from: line)
        guard !candidate.isEmpty else { return nil }
        if let headingKind = headingKind(for: candidate) {
            return headingKind
        }
        if line.hasPrefix("#") {
            return .section(candidate)
        }
        return nil
    }

    private func parseCallout(from line: String) -> (kind: StructuredCalloutKind, title: String)? {
        guard line.hasPrefix("["),
              let closingBracket = line.firstIndex(of: "]") else {
            return nil
        }

        let rawKind = String(line[line.index(after: line.startIndex)..<closingBracket])
        let title = String(line[line.index(after: closingBracket)...]).trimmed
        guard let kind = calloutKind(for: rawKind) else { return nil }
        return (kind, title)
    }

    private func headingKind(for line: String) -> SegmentKind? {
        switch canonicalHeading(line) {
        case "summary", "摘要":
            return .summary
        case "cuequestions", "studyprompts", "复习提示":
            return .cueQuestions
        case "keypoints", "highlights", "重点", "核心要点":
            return .keyPoints
        case "glossary", "术语":
            return .glossary
        case "studycards", "学习问答":
            return .studyCards
        case "actionitems", "explicittasks", "行动项", "明确任务":
            return .actionItems
        case "reviewquestions", "selfcheckquestions", "自测问题":
            return .reviewQuestions
        default:
            return nil
        }
    }

    private func canonicalHeading(_ line: String) -> String {
        stripHeadingPrefix(from: line)
            .lowercased()
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func stripHeadingPrefix(from line: String) -> String {
        var text = line.trimmed
        while text.hasPrefix("#") {
            text.removeFirst()
            text = text.trimmed
        }
        return text
    }

    private func calloutKind(for rawKind: String) -> StructuredCalloutKind? {
        switch rawKind.lowercased().replacingOccurrences(of: " ", with: "") {
        case "keyidea":
            return .keyIdea
        case "note":
            return .note
        case "warning":
            return .warning
        case "example":
            return .example
        default:
            return nil
        }
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let scalarSet = Set(line)
        return !line.isEmpty && (scalarSet == ["-"] || scalarSet == ["*"]) && line.count >= 3
    }

    private func paragraphs(from lines: [String]) -> [String] {
        var output: [String] = []
        var current: [String] = []

        for line in lines {
            if line.isEmpty {
                if !current.isEmpty {
                    output.append(current.joined(separator: " ").trimmed)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }
            current.append(line)
        }

        if !current.isEmpty {
            output.append(current.joined(separator: " ").trimmed)
        }

        return output.filter { !$0.isEmpty }
    }
}

private struct ParsedContent {
    var summary: String?
    var cueQuestions: [String] = []
    var keyPoints: [String] = []
    var sections: [StructuredSection] = []
    var glossary: [GlossaryItem] = []
    var callouts: [StructuredCallout] = []
    var studyCards: [StudyCard] = []
    var actionItems: [String] = []
    var reviewQuestions: [String] = []
    var hasStructuredContent = false
}

private enum SegmentKind {
    case summary
    case cueQuestions
    case keyPoints
    case glossary
    case studyCards
    case actionItems
    case reviewQuestions
    case section(String)
    case callout(kind: StructuredCalloutKind, title: String)
}

private struct SegmentPayload {
    let lines: [String]

    var trimmedLines: [String] {
        lines.map(\.trimmed)
    }

    var bullets: [String] {
        collectBullets(from: lines)
    }

    var bodyLines: [String] {
        lines.compactMap { line in
            let trimmed = line.trimmed
            guard !trimmed.isEmpty, bulletText(from: trimmed) == nil else { return nil }
            return trimmed
        }
    }

    var bodyText: String {
        joinedParagraphs(from: bodyLines)
    }

    var items: [String] {
        let bulletItems = bullets
        let paragraphItems = paragraphs(from: bodyLines)
        return unique(bulletItems + paragraphItems)
    }

    var glossary: [GlossaryItem] {
        uniqueGlossary(from: items)
    }

    var studyCards: [StudyCard] {
        parseStudyCards(from: lines)
    }

    var hasContent: Bool {
        !bodyText.isEmpty || !bullets.isEmpty
    }

    private func collectBullets(from lines: [String]) -> [String] {
        unique(
            lines.compactMap { line in
                bulletText(from: line.trimmed)
            }
        )
    }

    private func bulletText(from line: String) -> String? {
        guard !line.isEmpty else { return nil }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2)).trimmed.nonEmpty
        }

        let components = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = components.first, components.count == 2 else { return nil }
        let marker = String(first)
        if marker.last == ".", Int(marker.dropLast()) != nil {
            return String(components[1]).trimmed.nonEmpty
        }

        return nil
    }

    private func paragraphs(from lines: [String]) -> [String] {
        var output: [String] = []
        var current: [String] = []

        for line in lines {
            if line.isEmpty {
                if !current.isEmpty {
                    output.append(current.joined(separator: " ").trimmed)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }
            current.append(line)
        }

        if !current.isEmpty {
            output.append(current.joined(separator: " ").trimmed)
        }

        return output.filter { !$0.isEmpty }
    }

    private func joinedParagraphs(from lines: [String]) -> String {
        paragraphs(from: lines).joined(separator: "\n\n")
    }

    private func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { item in
            let trimmed = item.trimmed
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private func uniqueGlossary(from items: [String]) -> [GlossaryItem] {
        var seen = Set<String>()
        return items.compactMap { item in
            let separator: Character = item.contains("：") ? "：" : ":"
            let parts = item.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let term = String(parts[0]).trimmed
            let definition = String(parts[1]).trimmed
            guard !term.isEmpty, !definition.isEmpty else { return nil }
            let key = "\(term.lowercased())||\(definition.lowercased())"
            guard seen.insert(key).inserted else { return nil }
            return GlossaryItem(term: term, definition: definition)
        }
    }

    private func parseStudyCards(from lines: [String]) -> [StudyCard] {
        var cards: [StudyCard] = []
        var pendingQuestion: String?

        for line in lines.map(\.trimmed) where !line.isEmpty {
            let sanitized = bulletText(from: line) ?? line
            if let question = sanitizeStudyCardValue(sanitized, prefixes: ["Q:", "问："]) {
                pendingQuestion = question
                continue
            }
            if let answer = sanitizeStudyCardValue(sanitized, prefixes: ["A:", "答："]),
               let question = pendingQuestion {
                cards.append(StudyCard(question: question, answer: answer))
                pendingQuestion = nil
            }
        }

        return cards
    }

    private func sanitizeStudyCardValue(_ line: String, prefixes: [String]) -> String? {
        for prefix in prefixes where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmed.nonEmpty
        }
        return nil
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
