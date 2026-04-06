import Foundation

enum DraftGenerationMode: String, Codable, Equatable, Sendable {
    case finalDocument
    case chunkDigest
    case mergedDocument
}

struct ProviderDraftRequest: Codable, Equatable, Sendable {
    var rawText: String
    var goalType: GoalType
    var outputLanguage: OutputLanguage
    var contentTemplateName: String
    var visualTemplateName: String
    var generationMode: DraftGenerationMode = .finalDocument
}

struct ProviderDraftResponse: Codable, Equatable, Sendable {
    var title: String
    var summary: String
    var cueQuestions: [String]
    var keyPoints: [String]
    var sections: [StructuredSection]
    var glossary: [GlossaryItem]
    var callouts: [StructuredCallout]
    var studyCards: [StudyCard]
    var actionItems: [String]
    var reviewQuestions: [String]
    var renderedDocument: String

    init(
        title: String,
        summary: String,
        cueQuestions: [String] = [],
        keyPoints: [String],
        sections: [StructuredSection],
        glossary: [GlossaryItem] = [],
        callouts: [StructuredCallout] = [],
        studyCards: [StudyCard] = [],
        actionItems: [String],
        reviewQuestions: [String] = [],
        renderedDocument: String
    ) {
        self.title = title
        self.summary = summary
        self.cueQuestions = cueQuestions
        self.keyPoints = keyPoints
        self.sections = sections
        self.glossary = glossary
        self.callouts = callouts
        self.studyCards = studyCards
        self.actionItems = actionItems
        self.reviewQuestions = reviewQuestions
        self.renderedDocument = renderedDocument
    }

    static let empty = ProviderDraftResponse(
        title: "",
        summary: "",
        cueQuestions: [],
        keyPoints: [],
        sections: [],
        glossary: [],
        callouts: [],
        studyCards: [],
        actionItems: [],
        reviewQuestions: [],
        renderedDocument: ""
    )
}

struct ProviderValidationResult: Codable, Equatable, Sendable {
    var normalizedResponse: ProviderDraftResponse
    var warnings: [String]
}

struct ProviderHealthStatus: Equatable, Sendable {
    var isHealthy: Bool
    var summary: String
    var detail: String?
}

private extension ProviderHealthStatus {
    func with(detail: String?) -> ProviderHealthStatus {
        ProviderHealthStatus(isHealthy: isHealthy, summary: summary, detail: detail)
    }
}

protocol ProviderAdapter: Sendable {
    var prefersAggressiveChunking: Bool { get }
    func healthcheck() async -> Bool
    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse
    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult
    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion?
    func providerHealthStatus() async -> ProviderHealthStatus
    func cancelActiveWork() async
}

extension ProviderAdapter {
    var prefersAggressiveChunking: Bool { false }

    func providerHealthStatus() async -> ProviderHealthStatus {
        let healthy = await healthcheck()
        return ProviderHealthStatus(
            isHealthy: healthy,
            summary: healthy ? "Provider ready." : "Provider unavailable.",
            detail: nil
        )
    }

    func cancelActiveWork() async {}
}

protocol IntakeParser: Sendable {
    func parse(_ request: IntakeRequest) async throws -> ParsedDocument
}

enum DocumentProcessingError: Error {
    case noHealthyProvider
}

struct InteractiveDraftResult: Sendable {
    var version: DraftVersion
    var sourceText: String
    var shouldRefineInBackground: Bool
}

struct DocumentProcessingPipeline: Sendable {
    let parser: IntakeParser
    let primaryProvider: ProviderAdapter
    let fallbackProvider: ProviderAdapter?
    let chunkProvider: ProviderAdapter?
    let polishProvider: ProviderAdapter?
    let repairProvider: ProviderAdapter?

    init(
        parser: IntakeParser,
        primaryProvider: ProviderAdapter,
        fallbackProvider: ProviderAdapter? = nil,
        chunkProvider: ProviderAdapter? = nil,
        polishProvider: ProviderAdapter? = nil,
        repairProvider: ProviderAdapter? = nil
    ) {
        self.parser = parser
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
        self.chunkProvider = chunkProvider
        self.polishProvider = polishProvider
        self.repairProvider = repairProvider
    }

    func hasHealthyProvider() async -> Bool {
        if await primaryProvider.healthcheck() {
            return true
        }
        if let fallbackProvider, await fallbackProvider.healthcheck() {
            return true
        }
        return false
    }

    func providerHealthStatus() async -> ProviderHealthStatus {
        let primaryStatus = await primaryProvider.providerHealthStatus()
        let chunkStatus = await chunkProvider?.providerHealthStatus()
        let polishStatus = await polishProvider?.providerHealthStatus()
        let repairStatus = await repairProvider?.providerHealthStatus()

        var routeDetails: [String] = []
        if let chunkStatus {
            routeDetails.append("Chunk provider: \(chunkStatus.detailOrSummary)")
        }
        if let polishStatus {
            routeDetails.append("Polish provider: \(polishStatus.detailOrSummary)")
        }
        if let repairStatus {
            routeDetails.append("Repair provider: \(repairStatus.detailOrSummary)")
        }

        guard !primaryStatus.isHealthy, let fallbackProvider else {
            let detail = ([primaryStatus.detailOrSummary] + routeDetails)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return primaryStatus
                .with(detail: detail.isEmpty ? nil : detail)
        }

        let fallbackStatus = await fallbackProvider.providerHealthStatus()
        guard fallbackStatus.isHealthy else {
            return ProviderHealthStatus(
                isHealthy: false,
                summary: primaryStatus.summary,
                detail: ([primaryStatus.detailOrSummary, fallbackStatus.detailOrSummary] + routeDetails)
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            )
        }

        return ProviderHealthStatus(
            isHealthy: true,
            summary: "\(primaryStatus.summary) Fallback ready.",
            detail: (
                [
                    "Primary provider: \(primaryStatus.detailOrSummary)",
                    "Fallback provider: \(fallbackStatus.detailOrSummary)",
                ] + routeDetails
            )
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        )
    }

    func cancelActiveWork() async {
        await primaryProvider.cancelActiveWork()
        await fallbackProvider?.cancelActiveWork()
        await chunkProvider?.cancelActiveWork()
        await polishProvider?.cancelActiveWork()
        await repairProvider?.cancelActiveWork()
    }

    func process(
        intake: IntakeRequest,
        workspaceItemId: UUID,
        onStageChange: @Sendable (ProcessingStage) -> Void = { _ in }
    ) async throws -> DraftVersion {
        let interactive = try await processInteractive(
            intake: intake,
            workspaceItemId: workspaceItemId,
            onStageChange: onStageChange
        )
        guard interactive.shouldRefineInBackground else {
            return interactive.version
        }
        return try await refineDraftVersion(interactive.version, sourceText: interactive.sourceText)
    }

    func processInteractive(
        intake: IntakeRequest,
        workspaceItemId: UUID,
        onStageChange: @Sendable (ProcessingStage) -> Void = { _ in }
    ) async throws -> InteractiveDraftResult {
        onStageChange(.parseDocument)
        let parsed = try await parser.parse(intake)
        try Task.checkCancellation()

        onStageChange(.extractText)
        let sourceText = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()

        onStageChange(.extractImages)
        let images = parsed.images
        try Task.checkCancellation()

        onStageChange(.runOCR)
        let combinedContext = ([sourceText] + images.map(\.ocrText)).joined(separator: "\n")
        try Task.checkCancellation()

        onStageChange(.chunkAndMerge)
        let provider = try await activeProvider()
        let draft = try await generateDraft(
            using: provider,
            request: ProviderDraftRequest(
                rawText: combinedContext,
                goalType: intake.goalType,
                outputLanguage: intake.outputLanguage,
                contentTemplateName: intake.contentTemplateName,
                visualTemplateName: intake.visualTemplateName
            )
        )
        try Task.checkCancellation()

        onStageChange(.renderOutputLanguage)
        let localizedDraft = localized(response: draft, language: intake.outputLanguage)
        try Task.checkCancellation()

        onStageChange(.generateImageSuggestions)
        let imageSuggestions = try await images.asyncCompactMap { image in
            try Task.checkCancellation()
            return try await provider.analyzeImage(image, context: combinedContext)
        }
        try Task.checkCancellation()

        onStageChange(.completed)

        return InteractiveDraftResult(
            version: DraftVersion(
                workspaceItemId: workspaceItemId,
                goalType: intake.goalType,
                outputLanguage: intake.outputLanguage,
                editorDocument: localizedDraft.renderedDocument,
                structuredDoc: StructuredDocument(
                    title: localizedDraft.title,
                    summary: localizedDraft.summary,
                    cueQuestions: localizedDraft.cueQuestions,
                    keyPoints: localizedDraft.keyPoints,
                    sections: localizedDraft.sections,
                    glossary: localizedDraft.glossary,
                    callouts: localizedDraft.callouts,
                    studyCards: localizedDraft.studyCards,
                    actionItems: localizedDraft.actionItems,
                    reviewQuestions: localizedDraft.reviewQuestions,
                    imageSlots: imageSuggestions.map { ImageSlot(suggestionID: $0.id, caption: $0.title) },
                    exportMetadata: ExportMetadata(
                        contentTemplateName: intake.contentTemplateName,
                        visualTemplateName: intake.visualTemplateName,
                        preferredFormat: .pdf
                    )
                ),
                sourceRefs: parsed.sources,
                imageSuggestions: imageSuggestions,
                origin: .interactive
            ),
            sourceText: combinedContext,
            shouldRefineInBackground: shouldRefineInBackground()
        )
    }

    func refineDraftVersion(
        _ version: DraftVersion,
        sourceText: String
    ) async throws -> DraftVersion {
        let provider = try await activeProvider()
        let request = ProviderDraftRequest(
            rawText: sourceText,
            goalType: version.goalType,
            outputLanguage: version.outputLanguage,
            contentTemplateName: version.structuredDoc.exportMetadata.contentTemplateName,
            visualTemplateName: version.structuredDoc.exportMetadata.visualTemplateName
        )

        let polishedDraft = try await polishDraftIfNeeded(
            version.providerDraftResponse,
            request: request,
            sourceText: sourceText
        )
        try Task.checkCancellation()

        let validationProvider = try await activeValidationProvider(primary: provider)
        let validated = try await validationProvider.validateDraft(draft: polishedDraft, sourceText: sourceText)
        try Task.checkCancellation()

        let normalized = validated.normalizedResponse
        return DraftVersion(
            workspaceItemId: version.workspaceItemId,
            goalType: version.goalType,
            outputLanguage: version.outputLanguage,
            editorDocument: normalized.renderedDocument,
            structuredDoc: StructuredDocument(
                title: normalized.title,
                summary: normalized.summary,
                cueQuestions: normalized.cueQuestions,
                keyPoints: normalized.keyPoints,
                sections: normalized.sections,
                glossary: normalized.glossary,
                callouts: normalized.callouts,
                studyCards: normalized.studyCards,
                actionItems: normalized.actionItems,
                reviewQuestions: normalized.reviewQuestions,
                imageSlots: version.imageSuggestions.map { ImageSlot(suggestionID: $0.id, caption: $0.title) },
                exportMetadata: ExportMetadata(
                    contentTemplateName: version.structuredDoc.exportMetadata.contentTemplateName,
                    visualTemplateName: version.structuredDoc.exportMetadata.visualTemplateName,
                    preferredFormat: .pdf
                )
            ),
            sourceRefs: version.sourceRefs,
            imageSuggestions: version.imageSuggestions,
            origin: .refined,
            parentVersionId: version.id
        )
    }

    private func activeProvider() async throws -> ProviderAdapter {
        if await primaryProvider.healthcheck() {
            return primaryProvider
        }
        if let fallbackProvider, await fallbackProvider.healthcheck() {
            return fallbackProvider
        }
        throw DocumentProcessingError.noHealthyProvider
    }

    private func activeValidationProvider(primary: ProviderAdapter) async throws -> ProviderAdapter {
        if let repairProvider, await repairProvider.healthcheck() {
            return repairProvider
        }
        return primary
    }

    private func polishDraftIfNeeded(
        _ draft: ProviderDraftResponse,
        request: ProviderDraftRequest,
        sourceText: String
    ) async throws -> ProviderDraftResponse {
        guard shouldApplyPolish(request: request, sourceText: sourceText) else { return draft }
        guard let polishProvider, await polishProvider.healthcheck() else { return draft }
        let polished = try await polishProvider.validateDraft(draft: draft, sourceText: sourceText)
        return polished.normalizedResponse
    }

    private func shouldRefineInBackground() -> Bool {
        return true
    }

    private func shouldApplyPolish(request: ProviderDraftRequest, sourceText: String) -> Bool {
        if request.goalType == .formalDocument {
            return true
        }
        guard let inferredSourceLanguage = inferredSourceLanguage(from: sourceText) else {
            return false
        }
        return inferredSourceLanguage != request.outputLanguage
    }

    private func inferredSourceLanguage(from text: String) -> OutputLanguage? {
        let sample = String(text.prefix(4_000))
        let chineseCount = sample.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }.count
        let latinCount = sample.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar) && scalar.isASCII
        }.count

        if chineseCount >= max(20, latinCount / 3) {
            return .chinese
        }
        if latinCount >= max(60, chineseCount * 3) {
            return .english
        }
        return nil
    }

    private func generateDraft(
        using provider: ProviderAdapter,
        request: ProviderDraftRequest
    ) async throws -> ProviderDraftResponse {
        try Task.checkCancellation()
        let chunks = chunkedSourceTexts(
            from: request.rawText,
            aggressively: provider.prefersAggressiveChunking
        )
        guard chunks.count > 1 else {
            return try await provider.generateStructuredDraft(input: request)
        }

        let chunkDraftProvider = await activeChunkProvider(primary: provider)
        let chunkDrafts = try await withThrowingTaskGroup(
            of: (Int, ProviderDraftResponse).self,
            returning: [ProviderDraftResponse].self
        ) { group in
            for (index, chunk) in chunks.enumerated() {
                var chunkRequest = request
                chunkRequest.rawText = chunk
                chunkRequest.generationMode = .chunkDigest

                group.addTask {
                    let response = try await chunkDraftProvider.generateStructuredDraft(input: chunkRequest)
                    return (index, response)
                }
            }

            var orderedDrafts = Array<ProviderDraftResponse?>(repeating: nil, count: chunks.count)
            for try await (index, response) in group {
                orderedDrafts[index] = response
            }

            return try orderedDrafts.enumerated().map { index, response in
                guard let response else {
                    throw CancellationError()
                }
                return response
            }
        }

        try Task.checkCancellation()
        var mergedRequest = request
        mergedRequest.rawText = compactMergeContext(from: chunkDrafts, language: request.outputLanguage)
        mergedRequest.generationMode = .mergedDocument
        return try await provider.generateStructuredDraft(input: mergedRequest)
    }

    private func activeChunkProvider(primary: ProviderAdapter) async -> ProviderAdapter {
        if let chunkProvider, await chunkProvider.healthcheck() {
            return chunkProvider
        }
        return primary
    }

    private func chunkedSourceTexts(from rawText: String, aggressively: Bool = false) -> [String] {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }
        let threshold = aggressively ? DraftChunking.aggressiveThresholdCharacterCount : DraftChunking.thresholdCharacterCount
        let target = aggressively ? DraftChunking.aggressiveTargetChunkCharacterCount : DraftChunking.targetChunkCharacterCount
        let max = aggressively ? DraftChunking.aggressiveMaxChunkCharacterCount : DraftChunking.maxChunkCharacterCount
        guard normalized.count > threshold else { return [normalized] }

        let blockChunks = groupedTextUnits(
            blockUnits(from: normalized),
            separator: "\n\n",
            targetCharacterCount: target
        )
        if blockChunks.count > 1, blockChunks.allSatisfy({ $0.count <= max }) {
            return blockChunks
        }

        let sentenceChunks = groupedTextUnits(
            sentenceUnits(from: normalized),
            separator: " ",
            targetCharacterCount: target
        )
        return sentenceChunks.count > 1 ? sentenceChunks : [normalized]
    }

    private func blockUnits(from text: String) -> [String] {
        let doubleNewlineBlocks = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if doubleNewlineBlocks.count > 1 {
            return doubleNewlineBlocks
        }

        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func sentenceUnits(from text: String) -> [String] {
        text
            .split(whereSeparator: { [".", "!", "?", "。", "！", "？"].contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func groupedTextUnits(
        _ units: [String],
        separator: String,
        targetCharacterCount: Int
    ) -> [String] {
        guard !units.isEmpty else { return [] }

        var chunks: [String] = []
        var currentUnits: [String] = []
        var currentCount = 0

        for unit in units {
            let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedUnit.isEmpty else { continue }

            let separatorCount = currentUnits.isEmpty ? 0 : separator.count
            let candidateCount = currentCount + separatorCount + trimmedUnit.count

            if candidateCount > targetCharacterCount, !currentUnits.isEmpty {
                chunks.append(currentUnits.joined(separator: separator))
                currentUnits = [trimmedUnit]
                currentCount = trimmedUnit.count
            } else {
                currentUnits.append(trimmedUnit)
                currentCount = candidateCount
            }
        }

        if !currentUnits.isEmpty {
            chunks.append(currentUnits.joined(separator: separator))
        }

        return chunks
    }

    private func compactMergeContext(
        from chunkDrafts: [ProviderDraftResponse],
        language: OutputLanguage
    ) -> String {
        chunkDrafts.enumerated().map { index, draft in
            var lines: [String] = []
            let chunkLabel = language == .chinese ? "分块 \(index + 1)" : "Chunk \(index + 1)"
            let summaryLabel = language == .chinese ? "摘要" : "Summary"
            let keyPointsLabel = language == .chinese ? "关键点" : "Key Points"
            let sectionsLabel = language == .chinese ? "章节要点" : "Section Notes"
            let glossaryLabel = language == .chinese ? "术语" : "Glossary"
            let studyCardsLabel = language == .chinese ? "学习问答" : "Study Cards"
            let actionItemsLabel = language == .chinese ? "明确任务" : "Explicit Tasks"

            lines.append(chunkLabel)
            lines.append("\(summaryLabel): \(truncatedText(draft.summary, limit: 240))")

            if !draft.keyPoints.isEmpty {
                lines.append(keyPointsLabel)
                lines.append(contentsOf: draft.keyPoints.prefix(5).map { "- \(truncatedText($0, limit: 180))" })
            }

            if !draft.sections.isEmpty {
                lines.append(sectionsLabel)
                for section in draft.sections.prefix(2) {
                    lines.append("- \(section.title): \(truncatedText(section.body, limit: 220))")
                }
            }

            if !draft.glossary.isEmpty {
                lines.append(glossaryLabel)
                lines.append(contentsOf: draft.glossary.prefix(4).map {
                    "- \($0.term): \(truncatedText($0.definition, limit: 140))"
                })
            }

            if !draft.studyCards.isEmpty {
                lines.append(studyCardsLabel)
                lines.append(contentsOf: draft.studyCards.prefix(3).map {
                    "- \(language == .chinese ? "问" : "Q"): \(truncatedText($0.question, limit: 140)) | \(language == .chinese ? "答" : "A"): \(truncatedText($0.answer, limit: 180))"
                })
            }

            if !draft.actionItems.isEmpty {
                lines.append(actionItemsLabel)
                lines.append(contentsOf: draft.actionItems.prefix(4).map { "- \(truncatedText($0, limit: 160))" })
            }

            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    private func truncatedText(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "..."
    }

    private func localized(response: ProviderDraftResponse, language: OutputLanguage) -> ProviderDraftResponse {
        guard language == .english else { return response }

        let rendered = response.renderedDocument.contains("Summary") ? response.renderedDocument :
            "Summary\n\(response.summary)\n\nKey Points\n" + response.keyPoints.map { "- \($0)" }.joined(separator: "\n")

        return ProviderDraftResponse(
            title: response.title,
            summary: response.summary,
            cueQuestions: response.cueQuestions,
            keyPoints: response.keyPoints,
            sections: response.sections,
            glossary: response.glossary,
            callouts: response.callouts,
            studyCards: response.studyCards,
            actionItems: response.actionItems,
            reviewQuestions: response.reviewQuestions,
            renderedDocument: rendered
        )
    }
}

private extension DraftVersion {
    var providerDraftResponse: ProviderDraftResponse {
        ProviderDraftResponse(
            title: structuredDoc.title,
            summary: structuredDoc.summary,
            cueQuestions: structuredDoc.cueQuestions,
            keyPoints: structuredDoc.keyPoints,
            sections: structuredDoc.sections,
            glossary: structuredDoc.glossary,
            callouts: structuredDoc.callouts,
            studyCards: structuredDoc.studyCards,
            actionItems: structuredDoc.actionItems,
            reviewQuestions: structuredDoc.reviewQuestions,
            renderedDocument: editorDocument
        )
    }
}

extension Array {
    fileprivate func asyncCompactMap<T>(
        _ transform: (Element) async throws -> T?
    ) async throws -> [T] {
        var result: [T] = []
        for element in self {
            try Task.checkCancellation()
            if let mapped = try await transform(element) {
                result.append(mapped)
            }
        }
        return result
    }
}

private extension ProviderHealthStatus {
    var detailOrSummary: String {
        detail ?? summary
    }
}

private enum DraftChunking {
    static let thresholdCharacterCount = 6_000
    static let targetChunkCharacterCount = 2_800
    static let maxChunkCharacterCount = 4_000
    static let aggressiveThresholdCharacterCount = 4_200
    static let aggressiveTargetChunkCharacterCount = 2_000
    static let aggressiveMaxChunkCharacterCount = 2_800
}
