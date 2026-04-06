import Foundation

enum ProviderHTTP {
    static let requestTimeout: TimeInterval = 600
    static let resourceTimeout: TimeInterval = 1_800

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: configuration)
    }()
}

enum ProviderResponseParser {
    static func parse(_ raw: String) -> ProviderDraftResponse? {
        for candidate in responseCandidates(from: raw) {
            guard let parsed = parseCandidate(candidate) else { continue }
            return sanitize(parsed)
        }
        return nil
    }

    private static func parseCandidate(_ raw: String) -> ProviderDraftResponse? {
        guard let data = raw.data(using: .utf8) else { return nil }
        if let parsed = try? JSONDecoder().decode(ProviderDraftResponse.self, from: data) {
            return parsed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let title = json["title"] as? String ?? ""
        let summary = json["summary"] as? String ?? ""
        let cueQuestions = normalizeStrings(from: json["cueQuestions"] ?? json["studyPrompts"])
        let keyPoints = normalizeStrings(from: json["keyPoints"])
        let sections = normalizeSections(from: json["sections"])
        let glossary = normalizeGlossary(from: json["glossary"] ?? json["definitions"])
        let callouts = normalizeCallouts(from: json["callouts"], fallbackJSON: json)
        let studyCards = normalizeStudyCards(
            from: json["studyCards"]
                ?? json["reviewCards"]
                ?? json["flashcards"]
                ?? json["qaPairs"]
                ?? json["reviewQuestions"]
                ?? json["selfCheckQuestions"]
        )
        let actionItems = normalizeActionItems(from: json["actionItems"])
        let reviewQuestions = normalizeStrings(from: json["reviewQuestions"] ?? json["selfCheckQuestions"])
        let renderedDocument = json["renderedDocument"] as? String ?? ""

        guard !title.isEmpty || !summary.isEmpty || !renderedDocument.isEmpty else {
            return nil
        }

        return ProviderDraftResponse(
            title: title,
            summary: summary,
            cueQuestions: cueQuestions,
            keyPoints: keyPoints,
            sections: sections,
            glossary: glossary,
            callouts: callouts,
            studyCards: studyCards,
            actionItems: actionItems,
            reviewQuestions: reviewQuestions,
            renderedDocument: renderedDocument
        )
    }

    private static func responseCandidates(from raw: String) -> [String] {
        let thoughtStripped = stripReasoningArtifacts(from: raw)
        let fenceStripped = stripCodeFences(from: thoughtStripped)

        var candidates = [
            fenceStripped,
            thoughtStripped,
            stripCodeFences(from: raw),
            raw.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        if let extracted = extractFirstValidJSONObject(from: fenceStripped) {
            candidates.append(extracted)
        }
        if let extracted = extractFirstValidJSONObject(from: thoughtStripped) {
            candidates.append(extracted)
        }
        if let extracted = extractFirstValidJSONObject(from: raw) {
            candidates.append(extracted)
        }

        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private static func stripCodeFences(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        var lines = trimmed.components(separatedBy: .newlines)
        if !lines.isEmpty {
            lines.removeFirst()
        }
        if let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripReasoningArtifacts(from raw: String) -> String {
        var cleaned = raw.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = replacingMatches(
            pattern: #"(?is)<think>.*?</think>"#,
            in: cleaned,
            with: ""
        )
        cleaned = replacingMatches(
            pattern: #"(?im)^\s*thinking\.\.\.\s*$"#,
            in: cleaned,
            with: ""
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacingMatches(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func extractFirstValidJSONObject(from text: String) -> String? {
        let characters = Array(text)
        guard !characters.isEmpty else { return nil }

        for start in characters.indices where characters[start] == "{" {
            var depth = 0
            var isInsideString = false
            var isEscaped = false

            for end in start..<characters.count {
                let character = characters[end]

                if isEscaped {
                    isEscaped = false
                    continue
                }

                if character == "\\" && isInsideString {
                    isEscaped = true
                    continue
                }

                if character == "\"" {
                    isInsideString.toggle()
                    continue
                }

                if isInsideString {
                    continue
                }

                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1

                    guard depth >= 0 else { break }
                    guard depth == 0 else { continue }

                    let candidate = String(characters[start...end])
                    guard let data = candidate.data(using: .utf8) else { continue }
                    if (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] != nil {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    private static func sanitize(_ response: ProviderDraftResponse) -> ProviderDraftResponse {
        ProviderDraftResponse(
            title: sanitizeText(response.title),
            summary: sanitizeText(response.summary),
            cueQuestions: response.cueQuestions.map(sanitizeText).filter { !$0.isEmpty },
            keyPoints: response.keyPoints.map(sanitizeText).filter { !$0.isEmpty },
            sections: response.sections.compactMap { section in
                let title = sanitizeText(section.title)
                let body = sanitizeText(section.body)
                let bulletPoints = section.bulletPoints.map(sanitizeText).filter { !$0.isEmpty }
                guard !title.isEmpty || !body.isEmpty || !bulletPoints.isEmpty else { return nil }
                return StructuredSection(title: title, body: body, bulletPoints: bulletPoints)
            },
            glossary: response.glossary.compactMap { item in
                let term = sanitizeText(item.term)
                let definition = sanitizeText(item.definition)
                guard !term.isEmpty, !definition.isEmpty else { return nil }
                return GlossaryItem(term: term, definition: definition)
            },
            callouts: response.callouts.compactMap { callout in
                let title = sanitizeText(callout.title)
                let body = sanitizeText(callout.body)
                guard !title.isEmpty || !body.isEmpty else { return nil }
                return StructuredCallout(kind: callout.kind, title: title, body: body)
            },
            studyCards: response.studyCards.compactMap { card in
                let question = sanitizeText(card.question)
                let answer = sanitizeText(card.answer)
                guard !question.isEmpty, !answer.isEmpty else { return nil }
                return StudyCard(question: question, answer: answer)
            },
            actionItems: response.actionItems.map(sanitizeText).filter { !$0.isEmpty },
            reviewQuestions: response.reviewQuestions.map(sanitizeText).filter { !$0.isEmpty },
            renderedDocument: sanitizeText(response.renderedDocument)
        )
    }

    private static func sanitizeText(_ text: String) -> String {
        stripCodeFences(from: stripReasoningArtifacts(from: text))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeStrings(from value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { element in
            if let string = element as? String {
                return string
            }
            if let dictionary = element as? [String: Any] {
                return dictionary["item"] as? String
                    ?? dictionary["title"] as? String
                    ?? dictionary["question"] as? String
                    ?? dictionary["term"] as? String
            }
            return nil
        }
    }

    private static func normalizeSections(from value: Any?) -> [StructuredSection] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { element in
            guard let dictionary = element as? [String: Any],
                  let title = dictionary["title"] as? String else {
                return nil
            }

            let bulletPoints = normalizeStrings(from: dictionary["bulletPoints"] ?? dictionary["bullets"])
            let body = dictionary["body"] as? String
                ?? dictionary["summary"] as? String
                ?? bulletPoints.joined(separator: "\n")

            guard !body.isEmpty || !bulletPoints.isEmpty else { return nil }
            return StructuredSection(title: title, body: body, bulletPoints: bulletPoints)
        }
    }

    private static func normalizeGlossary(from value: Any?) -> [GlossaryItem] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { element in
            if let dictionary = element as? [String: Any] {
                let term = dictionary["term"] as? String ?? dictionary["title"] as? String ?? ""
                let definition = dictionary["definition"] as? String
                    ?? dictionary["body"] as? String
                    ?? dictionary["description"] as? String
                    ?? ""
                guard !term.isEmpty, !definition.isEmpty else { return nil }
                return GlossaryItem(term: term, definition: definition)
            }
            return nil
        }
    }

    private static func normalizeCallouts(from value: Any?, fallbackJSON: [String: Any]) -> [StructuredCallout] {
        var callouts: [StructuredCallout] = []
        if let array = value as? [Any] {
            callouts += array.compactMap { element in
                guard let dictionary = element as? [String: Any] else { return nil }
                let kindValue = (dictionary["kind"] as? String ?? dictionary["type"] as? String ?? "note")
                    .replacingOccurrences(of: " ", with: "")
                let kind = StructuredCalloutKind(rawValue: kindValue) ?? .note
                let title = dictionary["title"] as? String
                    ?? dictionary["label"] as? String
                    ?? defaultCalloutTitle(for: kind)
                let body = dictionary["body"] as? String
                    ?? dictionary["summary"] as? String
                    ?? dictionary["description"] as? String
                    ?? ""
                guard !body.isEmpty else { return nil }
                return StructuredCallout(kind: kind, title: title, body: body)
            }
        }

        if callouts.isEmpty {
            let fallbackMappings: [(String, StructuredCalloutKind)] = [
                ("warnings", .warning),
                ("examples", .example),
                ("notes", .note),
                ("highlights", .keyIdea),
            ]
            for (key, kind) in fallbackMappings {
                let items = normalizeStrings(from: fallbackJSON[key])
                callouts.append(contentsOf: items.map {
                    StructuredCallout(kind: kind, title: defaultCalloutTitle(for: kind), body: $0)
                })
            }
        }

        return callouts
    }

    private static func normalizeStudyCards(from value: Any?) -> [StudyCard] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { element in
            guard let dictionary = element as? [String: Any] else { return nil }
            let question = dictionary["question"] as? String
                ?? dictionary["prompt"] as? String
                ?? dictionary["front"] as? String
                ?? dictionary["title"] as? String
                ?? ""
            let answer = dictionary["answer"] as? String
                ?? dictionary["explanation"] as? String
                ?? dictionary["back"] as? String
                ?? dictionary["body"] as? String
                ?? dictionary["definition"] as? String
                ?? ""
            guard !question.isEmpty, !answer.isEmpty else { return nil }
            return StudyCard(question: question, answer: answer)
        }
    }

    private static func defaultCalloutTitle(for kind: StructuredCalloutKind) -> String {
        switch kind {
        case .keyIdea: return "Key Idea"
        case .note: return "Note"
        case .warning: return "Warning"
        case .example: return "Example"
        }
    }

    private static func normalizeActionItems(from value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { element in
            if let string = element as? String {
                return string
            }
            if let dictionary = element as? [String: Any] {
                return dictionary["item"] as? String
                    ?? dictionary["title"] as? String
                    ?? dictionary["description"] as? String
                    ?? dictionary["body"] as? String
            }
            return nil
        }
    }
}

enum ProviderRequestError: LocalizedError {
    case ollamaUnavailable(baseURL: String)
    case ollamaModelUnavailable(baseURL: String, modelName: String, availableModels: [String], serverMessage: String?)
    case ollamaRequestFailed(baseURL: String, modelName: String, statusCode: Int?, message: String)
    case customAPIMissingAPIKey(baseURL: String)
    case customAPIModelUnavailable(baseURL: String, modelName: String, availableModels: [String], serverMessage: String?)
    case customAPIRequestFailed(baseURL: String, modelName: String, statusCode: Int?, message: String)

    var errorDescription: String? {
        switch self {
        case let .ollamaUnavailable(baseURL):
            return "Ollama is unavailable at \(baseURL). Start Ollama first, then try again."
        case let .ollamaModelUnavailable(baseURL, modelName, availableModels, serverMessage):
            let available = availableModels.isEmpty ? "No installed models were reported." : "Available models: \(availableModels.joined(separator: ", "))."
            let suffix = serverMessage.map { " Server response: \($0)" } ?? ""
            return "Ollama is reachable at \(baseURL), but the model \"\(modelName)\" is not installed. \(available)\(suffix)"
        case let .ollamaRequestFailed(baseURL, modelName, statusCode, message):
            let status = statusCode.map { " (HTTP \($0))" } ?? ""
            return "Ollama failed while running \"\(modelName)\" at \(baseURL)\(status). \(message)"
        case let .customAPIMissingAPIKey(baseURL):
            return "Custom API at \(baseURL) needs an API key before it can run requests."
        case let .customAPIModelUnavailable(baseURL, modelName, availableModels, serverMessage):
            let available = availableModels.isEmpty ? "The API did not report any available models." : "Available models: \(availableModels.joined(separator: ", "))."
            let suffix = serverMessage.map { " Server response: \($0)" } ?? ""
            return "The custom API at \(baseURL) does not have the model \"\(modelName)\" available. \(available)\(suffix)"
        case let .customAPIRequestFailed(baseURL, modelName, statusCode, message):
            let status = statusCode.map { " (HTTP \($0))" } ?? ""
            return "The custom API failed while running \"\(modelName)\" at \(baseURL)\(status). \(message)"
        }
    }
}

private extension ProviderRequestError {
    var isTransient: Bool {
        switch self {
        case let .ollamaRequestFailed(_, _, statusCode, message),
             let .customAPIRequestFailed(_, _, statusCode, message):
            if let statusCode, [408, 409, 429, 500, 502, 503, 504].contains(statusCode) {
                return true
            }
            let lowercased = message.lowercased()
            return lowercased.contains("timed out")
                || lowercased.contains("timeout")
                || lowercased.contains("gateway")
                || lowercased.contains("temporarily unavailable")
        case .ollamaUnavailable, .ollamaModelUnavailable, .customAPIMissingAPIKey, .customAPIModelUnavailable:
            return false
        }
    }
}

private extension Error {
    var isTransientProviderFailure: Bool {
        if let providerError = self as? ProviderRequestError {
            return providerError.isTransient
        }
        if let urlError = self as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        let lowercased = localizedDescription.lowercased()
        return lowercased.contains("timed out") || lowercased.contains("gateway timeout")
    }
}

private func withTransientRetry<T>(
    maxAttempts: Int = 2,
    operation: () async throws -> T
) async throws -> T {
    precondition(maxAttempts > 0)

    var attempt = 0
    while true {
        attempt += 1
        do {
            return try await operation()
        } catch {
            guard attempt < maxAttempts, error.isTransientProviderFailure else {
                throw error
            }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 750_000_000)
        }
    }
}

struct HeuristicCurationProvider: ProviderAdapter {
    func healthcheck() async -> Bool { true }

    func providerHealthStatus() async -> ProviderHealthStatus {
        ProviderHealthStatus(
            isHealthy: true,
            summary: "Heuristic fallback ready.",
            detail: "Local heuristic drafting is available without contacting an external model."
        )
    }

    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse {
        let paragraphs = input.rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sentences = splitIntoSentences(paragraphs.joined(separator: " "))
        let summary = sentences.first ?? fallbackSummary(language: input.outputLanguage)
        let keyPoints = Array(sentences.prefix(input.generationMode == .chunkDigest ? 4 : 5))
        let cueQuestions = input.generationMode == .chunkDigest ? [] : buildCueQuestions(from: sentences, language: input.outputLanguage)
        let actionItems = sentences.filter { sentence in
            let lowercased = sentence.lowercased()
            return lowercased.contains("todo")
                || lowercased.contains("follow-up")
                || lowercased.contains("next step")
                || lowercased.contains("action item")
                || lowercased.contains("run ")
                || lowercased.contains("install ")
                || lowercased.contains("create ")
                || lowercased.contains("deploy ")
                || lowercased.contains("execute ")
                || lowercased.contains("mkdir ")
                || lowercased.contains("cd ")
                || lowercased.contains("forge ")
        }
        let sectionBodies = paragraphs.isEmpty ? splitIntoChunks(sentences, chunkSize: 4) : paragraphs.chunked(into: 2)
        let sectionTitles = suggestedSectionTitles(language: input.outputLanguage, count: max(sectionBodies.count, 1))
        let sections = zip(sectionTitles, sectionBodies).map { title, entries in
            StructuredSection(
                title: title,
                body: entries.joined(separator: "\n"),
                bulletPoints: Array(entries.prefix(4))
            )
        }
        let glossary = extractGlossary(from: input.rawText)
        let callouts = buildCallouts(
            summary: summary,
            sentences: sentences,
            language: input.outputLanguage
        )
        let studyCards = buildStudyCards(
            from: keyPoints.isEmpty ? [summary] : keyPoints,
            language: input.outputLanguage,
            preferredCount: input.generationMode == .chunkDigest ? 2 : 5
        )
        let reviewQuestions = input.generationMode == .chunkDigest ? [] : buildReviewQuestions(from: keyPoints, language: input.outputLanguage)
        let finalSections = sections.isEmpty ? [
            StructuredSection(
                title: input.outputLanguage == .chinese ? "整理结果" : "Curated Notes",
                body: sentences.joined(separator: "\n"),
                bulletPoints: Array(sentences.prefix(4))
            )
        ] : sections

        let title = deriveTitle(from: summary, language: input.outputLanguage)
        return ProviderDraftResponse(
            title: title,
            summary: summary,
            cueQuestions: cueQuestions,
            keyPoints: keyPoints.isEmpty ? [summary] : keyPoints,
            sections: finalSections,
            glossary: glossary,
            callouts: callouts,
            studyCards: studyCards,
            actionItems: actionItems,
            reviewQuestions: reviewQuestions,
            renderedDocument: renderDocument(
                title: title,
                summary: summary,
                cueQuestions: cueQuestions,
                keyPoints: keyPoints.isEmpty ? [summary] : keyPoints,
                sections: finalSections,
                glossary: glossary,
                callouts: callouts,
                studyCards: studyCards,
                actionItems: actionItems,
                reviewQuestions: reviewQuestions,
                language: input.outputLanguage
            )
        )
    }

    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        var normalized = draft
        if normalized.summary.isEmpty {
            normalized.summary = splitIntoSentences(sourceText).first ?? sourceText
        }
        if normalized.title.isEmpty {
            normalized.title = deriveTitle(from: normalized.summary, language: .english)
        }
        if normalized.sections.isEmpty {
            normalized.sections = [
                StructuredSection(
                    title: "Overview",
                    body: normalized.summary,
                    bulletPoints: normalized.keyPoints
                )
            ]
        }
        if normalized.studyCards.isEmpty {
            normalized.studyCards = buildStudyCards(
                from: normalized.keyPoints.isEmpty ? [normalized.summary] : normalized.keyPoints,
                language: .english,
                preferredCount: 4
            )
        }
        if normalized.reviewQuestions.isEmpty, !normalized.keyPoints.isEmpty {
            normalized.reviewQuestions = buildReviewQuestions(from: normalized.keyPoints, language: .english)
        }
        normalized.cueQuestions = uniqueNonEmptyStrings(normalized.cueQuestions)
        normalized.keyPoints = uniqueNonEmptyStrings(normalized.keyPoints)
        normalized.sections = uniqueSections(normalized.sections)
        normalized.glossary = uniqueGlossary(normalized.glossary)
        normalized.callouts = uniqueCallouts(normalized.callouts)
        normalized.studyCards = uniqueStudyCards(normalized.studyCards)
        normalized.actionItems = uniqueNonEmptyStrings(normalized.actionItems)
        normalized.reviewQuestions = uniqueNonEmptyStrings(normalized.reviewQuestions)
        return ProviderValidationResult(normalizedResponse: normalized, warnings: [])
    }

    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? {
        guard !image.ocrText.isEmpty || !image.summary.isEmpty else { return nil }
        return ImageSuggestion(
            title: image.title,
            summary: image.summary.isEmpty ? "Suggested supporting image" : image.summary,
            ocrText: image.ocrText
        )
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        text
            .split(whereSeparator: { [".", "!", "?", "。", "！", "？"].contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func deriveTitle(from summary: String, language: OutputLanguage) -> String {
        let prefix = summary.split(separator: " ").prefix(5).joined(separator: " ")
        if prefix.isEmpty {
            return language == .chinese ? "整理笔记" : "Curated Note"
        }
        return String(prefix)
    }

    private func fallbackSummary(language: OutputLanguage) -> String {
        language == .chinese ? "已根据输入内容生成结构化笔记。" : "Structured notes generated from the provided content."
    }

    private func buildCueQuestions(from sentences: [String], language: OutputLanguage) -> [String] {
        Array(sentences.prefix(3)).map { sentence in
            if language == .chinese {
                return "这段内容最想说明什么？\(sentence.prefix(20))"
            }
            return "What is the main idea behind: \(sentence.prefix(40))?"
        }
    }

    private func buildReviewQuestions(from keyPoints: [String], language: OutputLanguage) -> [String] {
        Array(keyPoints.prefix(3)).map { point in
            if language == .chinese {
                return "你能用自己的话解释这点吗：\(point)"
            }
            return "Can you explain this point in your own words: \(point)?"
        }
    }

    private func buildStudyCards(from keyPoints: [String], language: OutputLanguage, preferredCount: Int) -> [StudyCard] {
        Array(keyPoints.prefix(max(preferredCount, 1))).map { point in
            let trimmedPoint = point.trimmingCharacters(in: .whitespacesAndNewlines)
            if language == .chinese {
                return StudyCard(
                    question: "这条内容真正想表达什么：\(trimmedPoint)",
                    answer: trimmedPoint
                )
            }
            return StudyCard(
                question: "What should you remember about this idea: \(trimmedPoint)?",
                answer: trimmedPoint
            )
        }
    }

    private func buildCallouts(summary: String, sentences: [String], language: OutputLanguage) -> [StructuredCallout] {
        var callouts = [
            StructuredCallout(
                kind: .keyIdea,
                title: language == .chinese ? "核心观点" : "Core Idea",
                body: summary
            )
        ]

        if let warningSentence = sentences.first(where: {
            let lowercased = $0.lowercased()
            return lowercased.contains("risk")
                || lowercased.contains("warning")
                || lowercased.contains("注意")
                || lowercased.contains("不要")
        }) {
            callouts.append(
                StructuredCallout(
                    kind: .warning,
                    title: language == .chinese ? "注意事项" : "Watch Out",
                    body: warningSentence
                )
            )
        }

        if let exampleSentence = sentences.dropFirst().first {
            callouts.append(
                StructuredCallout(
                    kind: .example,
                    title: language == .chinese ? "例子" : "Example",
                    body: exampleSentence
                )
            )
        }

        return callouts
    }

    private func extractGlossary(from text: String) -> [GlossaryItem] {
        let tokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        let candidates = Set(tokens.filter { token in
            token == token.uppercased() || token.contains(where: \.isUppercase)
        })
        return Array(candidates.prefix(4)).sorted().map { token in
            GlossaryItem(term: token, definition: "Referenced in the source material and likely important to understand in context.")
        }
    }

    private func suggestedSectionTitles(language: OutputLanguage, count: Int) -> [String] {
        let chinese = ["概览", "核心机制", "关键细节", "延伸说明", "实践建议", "常见误区"]
        let english = ["Overview", "Core Mechanics", "Key Details", "Context", "Recommendations", "Common Pitfalls"]
        let titles = language == .chinese ? chinese : english
        return Array(titles.prefix(max(count, 1)))
    }

    private func splitIntoChunks(_ items: [String], chunkSize: Int) -> [[String]] {
        guard !items.isEmpty else { return [] }
        var chunks: [[String]] = []
        var current: [String] = []
        for item in items {
            current.append(item)
            if current.count == chunkSize {
                chunks.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private func renderDocument(
        title: String,
        summary: String,
        cueQuestions: [String],
        keyPoints: [String],
        sections: [StructuredSection],
        glossary: [GlossaryItem],
        callouts: [StructuredCallout],
        studyCards: [StudyCard],
        actionItems: [String],
        reviewQuestions: [String],
        language: OutputLanguage
    ) -> String {
        if language == .chinese {
            return """
            \(title)

            摘要
            \(summary)

            复习提示
            \(cueQuestions.map { "- \($0)" }.joined(separator: "\n"))

            重点
            \(keyPoints.map { "- \($0)" }.joined(separator: "\n"))

            \(sections.map {
                [
                    $0.title,
                    $0.body,
                    $0.bulletPoints.map { "- \($0)" }.joined(separator: "\n"),
                ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            }.joined(separator: "\n\n"))

            \(callouts.map { "[\($0.kind.rawValue)] \($0.title)\n\($0.body)" }.joined(separator: "\n\n"))

            术语
            \(glossary.map { "- \($0.term)：\($0.definition)" }.joined(separator: "\n"))

            学习问答
            \(studyCards.map { "- 问：\($0.question)\n  答：\($0.answer)" }.joined(separator: "\n"))

            行动项
            \(actionItems.map { "- \($0)" }.joined(separator: "\n"))

            自测问题
            \(reviewQuestions.map { "- \($0)" }.joined(separator: "\n"))
            """
        }

        return """
        \(title)

        Summary
        \(summary)

        Cue Questions
        \(cueQuestions.map { "- \($0)" }.joined(separator: "\n"))

        Key Points
        \(keyPoints.map { "- \($0)" }.joined(separator: "\n"))

        \(sections.map {
            [
                $0.title,
                $0.body,
                $0.bulletPoints.map { "- \($0)" }.joined(separator: "\n"),
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        }.joined(separator: "\n\n"))

        \(callouts.map { "[\($0.kind.rawValue)] \($0.title)\n\($0.body)" }.joined(separator: "\n\n"))

        Glossary
        \(glossary.map { "- \($0.term): \($0.definition)" }.joined(separator: "\n"))

        Study Cards
        \(studyCards.map { "- Q: \($0.question)\n  A: \($0.answer)" }.joined(separator: "\n"))

        Action Items
        \(actionItems.map { "- \($0)" }.joined(separator: "\n"))

        Review Questions
        \(reviewQuestions.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
}

struct LocalOllamaProvider: ProviderAdapter {
    var baseURL: URL
    var modelName: String
    var session: URLSession
    private let fallback = HeuristicCurationProvider()

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        modelName: String,
        session: URLSession = ProviderHTTP.session
    ) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.session = session
    }

    func healthcheck() async -> Bool {
        await providerHealthStatus().isHealthy
    }

    func providerHealthStatus() async -> ProviderHealthStatus {
        do {
            let models = try await installedModels()
            guard models.contains(modelName) else {
                return ProviderHealthStatus(
                    isHealthy: false,
                    summary: "Model not installed.",
                    detail: "Ollama is reachable at \(baseURL.absoluteString), but \"\(modelName)\" is missing. Available models: \(formatModelList(models))."
                )
            }

            return ProviderHealthStatus(
                isHealthy: true,
                summary: "Ollama ready.",
                detail: "Connected to \(baseURL.absoluteString) and ready to run \"\(modelName)\"."
            )
        } catch {
            return ProviderHealthStatus(
                isHealthy: false,
                summary: "Ollama unavailable.",
                detail: error.localizedDescription
            )
        }
    }

    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse {
        var request = URLRequest(url: baseURL.appending(path: "api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = providerPrompt(for: input)

        request.httpBody = try JSONEncoder().encode([
            "model": AnyEncodable(modelName),
            "prompt": AnyEncodable(prompt),
            "stream": AnyEncodable(false),
            "format": AnyEncodable("json"),
            "options": AnyEncodable(["temperature": 0.2]),
            // Qwen 3 defaults to reasoning traces; disable them for more stable JSON output.
            "think": AnyEncodable(prefersThinkingDisabled ? false : nil),
        ] as [String: AnyEncodable])

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw try await requestError(from: data, statusCode: httpResponse.statusCode)
        }

        let generated = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        if let errorMessage = generated.error, !errorMessage.isEmpty {
            throw try await requestError(message: errorMessage, statusCode: nil)
        }

        if let responseText = generated.response,
           let parsed = ProviderResponseParser.parse(responseText) {
            return parsed
        }

        return try await fallback.generateStructuredDraft(input: input)
    }

    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        try await fallback.validateDraft(draft: draft, sourceText: sourceText)
    }

    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? {
        try await fallback.analyzeImage(image, context: context)
    }

    func cancelActiveWork() async {
        var request = URLRequest(url: baseURL.appending(path: "api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try? JSONEncoder().encode([
            "model": AnyEncodable(modelName),
            "prompt": AnyEncodable(""),
            "stream": AnyEncodable(false),
            "keep_alive": AnyEncodable(0),
            "think": AnyEncodable(prefersThinkingDisabled ? false : nil),
        ] as [String: AnyEncodable])

        _ = try? await session.data(for: request)
    }

    private var prefersThinkingDisabled: Bool {
        let normalized = modelName.lowercased()
        return normalized.hasPrefix("qwen3") || normalized.hasPrefix("deepseek-r1")
    }

    private func installedModels() async throws -> [String] {
        var request = URLRequest(url: baseURL.appending(path: "api/tags"))
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ProviderRequestError.ollamaUnavailable(baseURL: baseURL.absoluteString)
            }
            guard httpResponse.statusCode == 200 else {
                let message = extractedMessage(from: data)
                throw ProviderRequestError.ollamaRequestFailed(
                    baseURL: baseURL.absoluteString,
                    modelName: modelName,
                    statusCode: httpResponse.statusCode,
                    message: message
                )
            }

            let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return tags.models.map(\.name)
        } catch let error as ProviderRequestError {
            throw error
        } catch {
            throw ProviderRequestError.ollamaUnavailable(baseURL: baseURL.absoluteString)
        }
    }

    private func requestError(from data: Data, statusCode: Int?) async throws -> ProviderRequestError {
        try await requestError(message: extractedMessage(from: data), statusCode: statusCode)
    }

    private func requestError(message: String, statusCode: Int?) async throws -> ProviderRequestError {
        if message.localizedCaseInsensitiveContains("model"),
           message.localizedCaseInsensitiveContains("not found") {
            let models = (try? await installedModels()) ?? []
            return .ollamaModelUnavailable(
                baseURL: baseURL.absoluteString,
                modelName: modelName,
                availableModels: models,
                serverMessage: message
            )
        }

        return .ollamaRequestFailed(
            baseURL: baseURL.absoluteString,
            modelName: modelName,
            statusCode: statusCode,
            message: message
        )
    }
}

struct OpenAICompatibleProvider: ProviderAdapter {
    var baseURL: URL
    var apiKey: String
    var modelName: String
    var session: URLSession
    private let fallback = HeuristicCurationProvider()

    init(
        baseURL: URL,
        apiKey: String,
        modelName: String,
        session: URLSession = ProviderHTTP.session
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.session = session
    }

    var prefersAggressiveChunking: Bool { true }

    func healthcheck() async -> Bool {
        await providerHealthStatus().isHealthy
    }

    func providerHealthStatus() async -> ProviderHealthStatus {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return ProviderHealthStatus(
                isHealthy: false,
                summary: "API key required.",
                detail: "Enter an API key for the custom endpoint at \(baseURL.absoluteString) before checking the model."
            )
        }

        do {
            let models = try await availableModels()
            guard models.contains(modelName) else {
                return ProviderHealthStatus(
                    isHealthy: false,
                    summary: "Model unavailable.",
                    detail: "The custom API at \(baseURL.absoluteString) does not list \"\(modelName)\". Available models: \(formatModelList(models))."
                )
            }

            return ProviderHealthStatus(
                isHealthy: true,
                summary: "Custom API ready.",
                detail: "Connected to \(baseURL.absoluteString) and ready to run \"\(modelName)\"."
            )
        } catch {
            return ProviderHealthStatus(
                isHealthy: false,
                summary: "Custom API unavailable.",
                detail: error.localizedDescription
            )
        }
    }

    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse {
        try await withTransientRetry {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                throw ProviderRequestError.customAPIMissingAPIKey(baseURL: baseURL.absoluteString)
            }

            var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let prompt = providerPrompt(for: input)

            request.httpBody = try JSONEncoder().encode(
                OpenAICompatibleRequest(
                    model: modelName,
                    messages: [
                        .init(role: "system", content: "You are a structured document curator."),
                        .init(role: "user", content: prompt),
                    ],
                    responseFormat: .init(type: "json_object")
                )
            )

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw try await requestError(from: data, statusCode: httpResponse.statusCode)
            }

            let completion = try JSONDecoder().decode(OpenAICompatibleResponse.self, from: data)
            guard let content = completion.choices.first?.message.content,
                  let parsed = ProviderResponseParser.parse(content) else {
                return try await fallback.generateStructuredDraft(input: input)
            }
            return parsed
        }
    }

    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ProviderRequestError.customAPIMissingAPIKey(baseURL: baseURL.absoluteString)
        }

        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = normalizationPrompt(for: modelName, draft: draft, sourceText: sourceText)
        request.httpBody = try JSONEncoder().encode(
            OpenAICompatibleRequest(
                model: modelName,
                messages: [
                    .init(role: "system", content: normalizationSystemPrompt(for: modelName)),
                    .init(role: "user", content: prompt),
                ],
                responseFormat: .init(type: "json_object")
            )
        )

        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw try await requestError(from: data, statusCode: httpResponse.statusCode)
            }

            let completion = try JSONDecoder().decode(OpenAICompatibleResponse.self, from: data)
            guard let content = completion.choices.first?.message.content,
                  let parsed = ProviderResponseParser.parse(content) else {
                return try await fallback.validateDraft(draft: draft, sourceText: sourceText)
            }

            let normalized = try await fallback.validateDraft(draft: parsed, sourceText: sourceText)
            return ProviderValidationResult(normalizedResponse: normalized.normalizedResponse, warnings: [])
        } catch {
            return try await fallback.validateDraft(draft: draft, sourceText: sourceText)
        }
    }

    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? {
        try await fallback.analyzeImage(image, context: context)
    }

    private func availableModels() async throws -> [String] {
        var request = URLRequest(url: baseURL.appending(path: "models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ProviderRequestError.customAPIRequestFailed(
                    baseURL: baseURL.absoluteString,
                    modelName: modelName,
                    statusCode: nil,
                    message: "No HTTP response was returned."
                )
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw try await requestError(from: data, statusCode: httpResponse.statusCode)
            }

            let payload = try JSONDecoder().decode(OpenAICompatibleModelsResponse.self, from: data)
            return payload.data.map(\.id)
        } catch let error as ProviderRequestError {
            throw error
        } catch {
            throw ProviderRequestError.customAPIRequestFailed(
                baseURL: baseURL.absoluteString,
                modelName: modelName,
                statusCode: nil,
                message: error.localizedDescription
            )
        }
    }

    private func requestError(from data: Data, statusCode: Int?) async throws -> ProviderRequestError {
        let message = extractedMessage(from: data)
        if message.localizedCaseInsensitiveContains("model"),
           (message.localizedCaseInsensitiveContains("not found") || message.localizedCaseInsensitiveContains("does not exist")) {
            let models = (try? await availableModels()) ?? []
            return .customAPIModelUnavailable(
                baseURL: baseURL.absoluteString,
                modelName: modelName,
                availableModels: models,
                serverMessage: message
            )
        }

        return .customAPIRequestFailed(
            baseURL: baseURL.absoluteString,
            modelName: modelName,
            statusCode: statusCode,
            message: message
        )
    }
}

struct AnthropicProvider: ProviderAdapter {
    var baseURL: URL
    var apiKey: String
    var modelName: String
    var session: URLSession
    private let fallback = HeuristicCurationProvider()

    init(
        baseURL: URL,
        apiKey: String,
        modelName: String,
        session: URLSession = ProviderHTTP.session
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.session = session
    }

    var prefersAggressiveChunking: Bool { true }

    func healthcheck() async -> Bool {
        await providerHealthStatus().isHealthy
    }

    func providerHealthStatus() async -> ProviderHealthStatus {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return ProviderHealthStatus(
                isHealthy: false,
                summary: "API key required.",
                detail: "Enter an API key for Anthropic before checking the model."
            )
        }

        do {
            let models = try await availableModels()
            guard models.contains(modelName) else {
                return ProviderHealthStatus(
                    isHealthy: false,
                    summary: "Model unavailable.",
                    detail: "Anthropic does not list \"\(modelName)\". Available models: \(formatModelList(models))."
                )
            }

            return ProviderHealthStatus(
                isHealthy: true,
                summary: "Anthropic ready.",
                detail: "Connected to \(baseURL.absoluteString) and ready to run \"\(modelName)\"."
            )
        } catch {
            return ProviderHealthStatus(
                isHealthy: false,
                summary: "Anthropic unavailable.",
                detail: error.localizedDescription
            )
        }
    }

    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse {
        let prompt = providerPrompt(for: input)
        let content = try await sendMessage(
            system: "You are a structured document curator. Return JSON only.",
            prompt: prompt
        )

        guard let parsed = ProviderResponseParser.parse(content) else {
            return try await fallback.generateStructuredDraft(input: input)
        }
        return parsed
    }

    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        let prompt = normalizationPrompt(for: modelName, draft: draft, sourceText: sourceText)

        do {
            let content = try await sendMessage(
                system: normalizationSystemPrompt(for: modelName),
                prompt: prompt
            )

            guard let parsed = ProviderResponseParser.parse(content) else {
                return try await fallback.validateDraft(draft: draft, sourceText: sourceText)
            }

            let normalized = try await fallback.validateDraft(draft: parsed, sourceText: sourceText)
            return ProviderValidationResult(normalizedResponse: normalized.normalizedResponse, warnings: [])
        } catch {
            return try await fallback.validateDraft(draft: draft, sourceText: sourceText)
        }
    }

    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? {
        try await fallback.analyzeImage(image, context: context)
    }

    private func sendMessage(system: String, prompt: String) async throws -> String {
        try await withTransientRetry {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                throw ProviderRequestError.customAPIMissingAPIKey(baseURL: baseURL.absoluteString)
            }

            var request = URLRequest(url: baseURL.appending(path: "v1/messages"))
            request.httpMethod = "POST"
            request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            request.httpBody = try JSONEncoder().encode(
                AnthropicMessagesRequest(
                    model: modelName,
                    system: system,
                    messages: [.init(role: "user", content: prompt)]
                )
            )

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw ProviderRequestError.customAPIRequestFailed(
                    baseURL: baseURL.absoluteString,
                    modelName: modelName,
                    statusCode: httpResponse.statusCode,
                    message: extractedMessage(from: data)
                )
            }

            let completion = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
            let text = completion.content
                .filter { $0.type == "text" }
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw ProviderRequestError.customAPIRequestFailed(
                    baseURL: baseURL.absoluteString,
                    modelName: modelName,
                    statusCode: nil,
                    message: "Anthropic returned an empty text response."
                )
            }

            return text
        }
    }

    private func availableModels() async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ProviderRequestError.customAPIMissingAPIKey(baseURL: baseURL.absoluteString)
        }

        var request = URLRequest(url: baseURL.appending(path: "v1/models"))
        request.httpMethod = "GET"
        request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderRequestError.customAPIRequestFailed(
                baseURL: baseURL.absoluteString,
                modelName: modelName,
                statusCode: nil,
                message: "No HTTP response was returned."
            )
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ProviderRequestError.customAPIRequestFailed(
                baseURL: baseURL.absoluteString,
                modelName: modelName,
                statusCode: httpResponse.statusCode,
                message: extractedMessage(from: data)
            )
        }

        let payload = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
        return payload.data.map(\.id)
    }
}

struct GeminiProvider: ProviderAdapter {
    var baseURL: URL
    var apiKey: String
    var modelName: String
    var session: URLSession
    private let fallback = HeuristicCurationProvider()

    init(
        baseURL: URL,
        apiKey: String,
        modelName: String,
        session: URLSession = ProviderHTTP.session
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.session = session
    }

    var prefersAggressiveChunking: Bool { true }

    func healthcheck() async -> Bool {
        await providerHealthStatus().isHealthy
    }

    func providerHealthStatus() async -> ProviderHealthStatus {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return ProviderHealthStatus(
                isHealthy: false,
                summary: "API key required.",
                detail: "Enter an API key for Google Gemini before checking the model."
            )
        }

        do {
            let models = try await availableModels()
            guard models.contains(modelName) else {
                return ProviderHealthStatus(
                    isHealthy: false,
                    summary: "Model unavailable.",
                    detail: "Gemini does not list \"\(modelName)\". Available models: \(formatModelList(models))."
                )
            }

            return ProviderHealthStatus(
                isHealthy: true,
                summary: "Gemini ready.",
                detail: "Connected to \(baseURL.absoluteString) and ready to run \"\(modelName)\"."
            )
        } catch {
            return ProviderHealthStatus(
                isHealthy: false,
                summary: "Gemini unavailable.",
                detail: error.localizedDescription
            )
        }
    }

    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse {
        let prompt = providerPrompt(for: input)
        let content = try await generateText(
            system: "You are a structured document curator. Return JSON only.",
            prompt: prompt
        )

        guard let parsed = ProviderResponseParser.parse(content) else {
            return try await fallback.generateStructuredDraft(input: input)
        }
        return parsed
    }

    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        let prompt = normalizationPrompt(for: modelName, draft: draft, sourceText: sourceText)

        do {
            let content = try await generateText(
                system: normalizationSystemPrompt(for: modelName),
                prompt: prompt
            )

            guard let parsed = ProviderResponseParser.parse(content) else {
                return try await fallback.validateDraft(draft: draft, sourceText: sourceText)
            }

            let normalized = try await fallback.validateDraft(draft: parsed, sourceText: sourceText)
            return ProviderValidationResult(normalizedResponse: normalized.normalizedResponse, warnings: [])
        } catch {
            return try await fallback.validateDraft(draft: draft, sourceText: sourceText)
        }
    }

    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? {
        try await fallback.analyzeImage(image, context: context)
    }

    private func generateText(system: String, prompt: String) async throws -> String {
        try await withTransientRetry {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                throw ProviderRequestError.customAPIMissingAPIKey(baseURL: baseURL.absoluteString)
            }

            var request = URLRequest(url: baseURL.appending(path: "v1beta/models/\(modelName):generateContent"))
            request.httpMethod = "POST"
            request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                GeminiGenerateContentRequest(
                    systemInstruction: .init(parts: [.init(text: system)]),
                    contents: [.init(role: "user", parts: [.init(text: prompt)])],
                    generationConfig: .init(
                        responseMimeType: "application/json",
                        temperature: 0.2
                    )
                )
            )

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw ProviderRequestError.customAPIRequestFailed(
                    baseURL: baseURL.absoluteString,
                    modelName: modelName,
                    statusCode: httpResponse.statusCode,
                    message: extractedMessage(from: data)
                )
            }

            let completion = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
            let text = completion.candidates
                .flatMap { $0.content.parts }
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw ProviderRequestError.customAPIRequestFailed(
                    baseURL: baseURL.absoluteString,
                    modelName: modelName,
                    statusCode: nil,
                    message: "Gemini returned an empty text response."
                )
            }

            return text
        }
    }

    private func availableModels() async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ProviderRequestError.customAPIMissingAPIKey(baseURL: baseURL.absoluteString)
        }

        var request = URLRequest(url: baseURL.appending(path: "v1beta/models"))
        request.httpMethod = "GET"
        request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderRequestError.customAPIRequestFailed(
                baseURL: baseURL.absoluteString,
                modelName: modelName,
                statusCode: nil,
                message: "No HTTP response was returned."
            )
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ProviderRequestError.customAPIRequestFailed(
                baseURL: baseURL.absoluteString,
                modelName: modelName,
                statusCode: httpResponse.statusCode,
                message: extractedMessage(from: data)
            )
        }

        let payload = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        return payload.models.map { model in
            let name = model.name
            return name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
        }
    }
}

struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeImpl = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}

private struct OllamaGenerateResponse: Decodable {
    var response: String?
    var error: String?
}

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        var name: String
    }

    var models: [Model]
}

private struct OpenAICompatibleRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    struct ResponseFormat: Encodable {
        var type: String
    }

    var model: String
    var messages: [Message]
    var responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages
        case responseFormat = "response_format"
    }
}

private struct OpenAICompatibleResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String
        }

        var message: Message
    }

    var choices: [Choice]
}

private struct OpenAICompatibleModelsResponse: Decodable {
    struct Model: Decodable {
        var id: String
    }

    var data: [Model]
}

private struct AnthropicMessagesRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var system: String
    var messages: [Message]
    var maxTokens: Int = 8_192

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicMessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        var type: String
        var text: String?
    }

    var content: [ContentBlock]
}

private struct AnthropicModelsResponse: Decodable {
    struct Model: Decodable {
        var id: String
    }

    var data: [Model]
}

private struct GeminiGenerateContentRequest: Encodable {
    struct Content: Encodable {
        var role: String?
        var parts: [Part]
    }

    struct Part: Encodable {
        var text: String
    }

    struct GenerationConfig: Encodable {
        var responseMimeType: String
        var temperature: Double

        enum CodingKeys: String, CodingKey {
            case temperature
            case responseMimeType = "responseMimeType"
        }
    }

    var systemInstruction: Content
    var contents: [Content]
    var generationConfig: GenerationConfig

    enum CodingKeys: String, CodingKey {
        case contents, generationConfig
        case systemInstruction = "system_instruction"
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                var text: String?
            }

            var parts: [Part]
        }

        var content: Content
    }

    var candidates: [Candidate]
}

private struct GeminiModelsResponse: Decodable {
    struct Model: Decodable {
        var name: String
    }

    var models: [Model]
}

private struct StandardAPIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        var message: String
    }

    var error: Payload
}

private func extractedMessage(from data: Data) -> String {
    if let ollamaError = try? JSONDecoder().decode(OllamaGenerateResponse.self, from: data),
       let message = ollamaError.error,
       !message.isEmpty {
        return message
    }

    if let envelope = try? JSONDecoder().decode(StandardAPIErrorEnvelope.self, from: data) {
        return envelope.error.message
    }

    let fallback = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return fallback?.isEmpty == false ? fallback! : "The provider returned an empty error payload."
}

private func formatModelList(_ models: [String]) -> String {
    guard !models.isEmpty else { return "none reported" }
    let preview = Array(models.prefix(6))
    let suffix = models.count > preview.count ? ", ..." : ""
    return preview.joined(separator: ", ") + suffix
}

private func providerPrompt(for input: ProviderDraftRequest) -> String {
    switch input.generationMode {
    case .chunkDigest:
        return chunkDigestPrompt(for: input)
    case .finalDocument:
        return finalLearningPrompt(for: input, mergedFromChunks: false)
    case .mergedDocument:
        return finalLearningPrompt(for: input, mergedFromChunks: true)
    }
}

private func repairPrompt(for draft: ProviderDraftResponse, sourceText: String) -> String {
    let existingJSON = (try? JSONEncoder().encode(draft))
        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

    return """
    Repair and normalize the existing document draft into one valid JSON object that matches this schema exactly:
    {
      "title": String,
      "summary": String,
      "cueQuestions": [String],
      "keyPoints": [String],
      "sections": [{"title": String, "body": String, "bulletPoints": [String]}],
      "glossary": [{"term": String, "definition": String}],
      "callouts": [{"kind": "keyIdea"|"note"|"warning"|"example", "title": String, "body": String}],
      "studyCards": [{"question": String, "answer": String}],
      "actionItems": [String],
      "reviewQuestions": [String],
      "renderedDocument": String
    }

    Requirements:
    - Return JSON only.
    - Preserve the user's language and intent.
    - Do not invent facts that are unsupported by the source text.
    - Fix malformed, missing, duplicated, or weakly-structured fields.
    - Ensure sections, studyCards, glossary, and actionItems are clean arrays.
    - Ensure renderedDocument is coherent and matches the normalized structure.
    - Remove chain-of-thought, scratchpad text, and invalid schema fields.

    Source text:
    \(sourceText)

    Existing draft JSON:
    \(existingJSON)
    """
}

private func polishPrompt(for draft: ProviderDraftResponse, sourceText: String) -> String {
    let existingJSON = (try? JSONEncoder().encode(draft))
        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

    return """
    Rewrite the existing document draft into better final prose while preserving facts and the required JSON schema.

    Requirements:
    - Return JSON only.
    - Preserve every grounded fact from the source text.
    - If the existing draft language differs from the dominant source language, translate into the draft language cleanly and naturally.
    - Improve flow, wording, clarity, and tone.
    - Keep the schema exactly the same:
      title, summary, cueQuestions, keyPoints, sections, glossary, callouts, studyCards, actionItems, reviewQuestions, renderedDocument
    - Make renderedDocument read like a polished final deliverable, not a rough draft.
    - Do not add unsupported facts.
    - Do not output chain-of-thought or extra commentary.

    Source text:
    \(sourceText)

    Existing draft JSON:
    \(existingJSON)
    """
}

private func normalizationSystemPrompt(for modelName: String) -> String {
    isPolishModel(modelName)
        ? "You polish, rewrite, and translate structured document JSON while preserving schema."
        : "You repair structured JSON outputs for document workflows."
}

private func normalizationPrompt(for modelName: String, draft: ProviderDraftResponse, sourceText: String) -> String {
    isPolishModel(modelName)
        ? polishPrompt(for: draft, sourceText: sourceText)
        : repairPrompt(for: draft, sourceText: sourceText)
}

private func isPolishModel(_ modelName: String) -> Bool {
    HostedService.allCases.map(\.recommendedPolishModel).contains(modelName)
}

private func finalLearningPrompt(for input: ProviderDraftRequest, mergedFromChunks: Bool) -> String {
    let sourceLabel: String
    if mergedFromChunks {
        sourceLabel = input.outputLanguage == .chinese
            ? "下面的 Source 不是原文，而是长文本分块后的摘要与提炼结果。请去重、合并、纠正重复表达，并输出一份完整的学习型笔记。"
            : "The Source below is not the raw original text. It is a merged digest produced from chunks of a longer document. Deduplicate overlaps, merge related points, and produce one complete learning-oriented note."
    } else {
        sourceLabel = input.outputLanguage == .chinese
            ? "下面的 Source 是原始内容。请直接基于原文输出学习型笔记。"
            : "The Source below is the original content. Produce the learning-oriented note directly from it."
    }

    return """
    Return ONLY valid JSON with these keys:
    - title: string
    - summary: string
    - cueQuestions: string[]
    - keyPoints: string[]
    - sections: { "title": string, "body": string, "bulletPoints": string[] }[]
    - glossary: { "term": string, "definition": string }[]
    - callouts: { "kind": "keyIdea" | "note" | "warning" | "example", "title": string, "body": string }[]
    - studyCards: { "question": string, "answer": string }[]
    - actionItems: string[]
    - reviewQuestions: string[]
    - renderedDocument: string

    Requirements:
    - Output language must be \(input.outputLanguage.rawValue).
    - Goal type is \(input.goalType.rawValue).
    - Content template is \(input.contentTemplateName).
    - Visual template is \(input.visualTemplateName).
    - Never output chain-of-thought, reasoning traces, scratchpad text, "Thinking...", or <think> tags.
    - Never include any text before or after the JSON object.
    - \(learningNoteRequirements(language: input.outputLanguage))
    - The notes must be detailed, specific, and not shallow.
    - Preserve important facts, numbers, terminology, comparisons, commands, and design decisions from the source.
    - Prefer 4-8 key points when the source supports it.
    - Prefer 3-6 substantive sections, each with a strong summary body and 2-5 bullet points when possible.
    - Sections should teach the material, not just restate it; explain what, why, and how when the source supports it.
    - Use glossary only for terms that truly matter.
    - Use callouts only for grounded insights such as key ideas, warnings, or examples from the source.
    - Include 3-6 studyCards when the material is educational or technical. Each study card must have a direct answer, not just a question.
    - If the source includes quiz questions or multiple-choice questions, convert the most useful ones into studyCards with the correct answer and a short explanation in the answer.
    - Include 2-4 cue questions inspired by study-note formats when useful.
    - Include 2-4 review questions when the material is educational or technical, but keep them as quick self-check prompts and avoid duplicating studyCards exactly.
    - Leave actionItems empty unless the source clearly contains real tasks, commands, follow-ups, or next steps.
    - Do not invent details that are not supported by the source.
    - renderedDocument should be polished markdown that reflects the same richer structure.

    Template guidance:
    \(templateGuidance(for: input.contentTemplateName, goalType: input.goalType, language: input.outputLanguage))

    Source guidance:
    \(sourceLabel)

    Source:
    \(input.rawText)
    """
}

private func chunkDigestPrompt(for input: ProviderDraftRequest) -> String {
    """
    Return ONLY valid JSON with these keys:
    - title: string
    - summary: string
    - cueQuestions: string[]
    - keyPoints: string[]
    - sections: { "title": string, "body": string, "bulletPoints": string[] }[]
    - glossary: { "term": string, "definition": string }[]
    - callouts: { "kind": "keyIdea" | "note" | "warning" | "example", "title": string, "body": string }[]
    - studyCards: { "question": string, "answer": string }[]
    - actionItems: string[]
    - reviewQuestions: string[]
    - renderedDocument: string

    Requirements:
    - Output language must be \(input.outputLanguage.rawValue).
    - This Source is only one chunk of a longer document.
    - Never output chain-of-thought, reasoning traces, scratchpad text, "Thinking...", or <think> tags.
    - Never include any text before or after the JSON object.
    - Extract a compact digest for later merge, not the final polished handout.
    - Focus on the most important concepts, why they matter, concrete facts, numbers, terms, commands, examples, and comparisons in this chunk.
    - If this chunk contains quiz or multiple-choice content, convert the most useful items into studyCards with the correct answer and one-sentence justification.
    - Keep summary to 1-2 sentences.
    - Prefer 3-5 key points.
    - Prefer 1-3 sections with concise but information-dense explanations.
    - Include 1-3 studyCards when the chunk supports it, and every study card must have a real answer.
    - Keep cueQuestions and reviewQuestions empty unless they add clear value.
    - Leave actionItems empty unless the chunk contains explicit commands, real tasks, or follow-up steps.
    - Do not invent missing context.
    - renderedDocument should be short markdown useful for merge.

    Source:
    \(input.rawText)
    """
}

private func learningNoteRequirements(language: OutputLanguage) -> String {
    if language == .chinese {
        return """
        请把下面内容整理成“学习型笔记”，不是普通摘要。
        要求：
        1. 先讲清楚核心概念、作用、为什么重要。
        2. 保留原文里的关键事实、数字、术语、命令、例子和对比。
        3. 如果原文里有 quiz / 选择题，不要只抄题目，要输出“问题 + 正确答案 + 1句理由”。
        4. 生成 4-6 个学习问答卡，每个都必须有明确答案。
        5. 自测问题可以保留，但不要和学习问答重复。
        6. 没有明确任务时，不要生成泛化的任务清单。
        7. 不要重复章节，不要空话。
        """
    }

    return """
    Create learning-oriented notes, not a plain summary.
    Requirements:
    1. Explain the core concept, what it does, and why it matters first.
    2. Preserve key facts, numbers, terms, commands, examples, and comparisons from the source.
    3. If the source contains quiz or multiple-choice material, convert it into “question + correct answer + one-sentence reason”.
    4. Generate 4-6 study cards, each with a clear answer.
    5. Review questions may remain, but they must not duplicate the study cards.
    6. Do not generate generic task lists when the source does not contain explicit tasks.
    7. Avoid repeated sections and avoid filler.
    """
}

private func templateGuidance(for templateName: String, goalType: GoalType, language: OutputLanguage) -> String {
    let lowercased = templateName.lowercased()
    if lowercased.contains("lecture") || lowercased.contains("study") || lowercased.contains("structured") {
        return language == .chinese
            ? "把内容写成真正可学习的讲义式笔记：先给摘要，再给复习提示、重点、分章节讲解、术语、注意事项、例子，以及带明确答案的学习问答。若原文里有题目或选择题，要优先转成“问题 + 正确答案 + 简短解释”，不要只抄题目。"
            : "Write the result like a lecture handout that genuinely helps someone study: summary first, then cue questions, key points, sectioned explanations, glossary terms, warnings, examples, and answered study cards. If the source includes quiz or multiple-choice prompts, convert the most useful ones into question-plus-answer explanations instead of copying bare questions."
    }
    if lowercased.contains("formal") || goalType == .formalDocument {
        return language == .chinese
            ? "写得更像正式说明文档，但仍要保留足够的技术细节和结构层次。"
            : "Write it like a polished formal document while still preserving technical detail and teaching value."
    }
    if lowercased.contains("action") || goalType == .actionItems {
        return language == .chinese
            ? "行动项必须具体，并保留上下文说明，避免只有碎片化待办。"
            : "Action items should be concrete and contextualized, not just a shallow to-do list."
    }
    return language == .chinese
        ? "请输出结构化、信息密度高、可用于学习和导出的笔记；优先帮助读者理解与记忆，而不是只罗列内容。"
        : "Produce structured, information-dense notes optimized for learning and retention, not just content listing."
}

private func uniqueNonEmptyStrings(_ items: [String]) -> [String] {
    var seen: Set<String> = []
    return items.compactMap { item in
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = trimmed
            .replacingOccurrences(of: "\r\n", with: "\n")
            .lowercased()
        guard seen.insert(key).inserted else { return nil }
        return trimmed
    }
}

private func uniqueSections(_ sections: [StructuredSection]) -> [StructuredSection] {
    var seen: Set<String> = []
    return sections.compactMap { section -> StructuredSection? in
        let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = section.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let bullets = uniqueNonEmptyStrings(section.bulletPoints)
        guard !title.isEmpty || !body.isEmpty || !bullets.isEmpty else { return nil }
        let key = [
            title.lowercased(),
            body.lowercased(),
            bullets.map { $0.lowercased() }.joined(separator: "|")
        ].joined(separator: "||")
        guard seen.insert(key).inserted else { return nil }
        return StructuredSection(title: title, body: body, bulletPoints: bullets)
    }
}

private func uniqueGlossary(_ items: [GlossaryItem]) -> [GlossaryItem] {
    var seen: Set<String> = []
    return items.compactMap { item in
        let term = item.term.trimmingCharacters(in: .whitespacesAndNewlines)
        let definition = item.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !definition.isEmpty else { return nil }
        let key = "\(term.lowercased())||\(definition.lowercased())"
        guard seen.insert(key).inserted else { return nil }
        return GlossaryItem(term: term, definition: definition)
    }
}

private func uniqueCallouts(_ items: [StructuredCallout]) -> [StructuredCallout] {
    var seen: Set<String> = []
    return items.compactMap { item in
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let key = "\(item.kind.rawValue)||\(title.lowercased())||\(body.lowercased())"
        guard seen.insert(key).inserted else { return nil }
        return StructuredCallout(kind: item.kind, title: title, body: body)
    }
}

private func uniqueStudyCards(_ items: [StudyCard]) -> [StudyCard] {
    var seen: Set<String> = []
    return items.compactMap { item in
        let question = item.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = item.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !answer.isEmpty else { return nil }
        let key = "\(question.lowercased())||\(answer.lowercased())"
        guard seen.insert(key).inserted else { return nil }
        return StudyCard(question: question, answer: answer)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { start in
            let end = Swift.min(start + size, count)
            return Array(self[start..<end])
        }
    }
}
