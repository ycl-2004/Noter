import Foundation
@testable import NotesCurator

struct StubProvider: ProviderAdapter {
    let isHealthy: Bool
    let response: ProviderDraftResponse

    func healthcheck() async -> Bool { isHealthy }
    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse { response }
    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        ProviderValidationResult(normalizedResponse: draft, warnings: [])
    }
    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? {
        ImageSuggestion(title: image.title, summary: image.summary, ocrText: image.ocrText)
    }
}

actor DraftRequestRecorder {
    private var requests: [ProviderDraftRequest] = []

    func record(_ request: ProviderDraftRequest) {
        requests.append(request)
    }

    func snapshot() -> [ProviderDraftRequest] {
        requests
    }
}

actor ValidationRecorder {
    private var drafts: [ProviderDraftResponse] = []

    func record(_ draft: ProviderDraftResponse) {
        drafts.append(draft)
    }

    func snapshot() -> [ProviderDraftResponse] {
        drafts
    }
}

actor ValidationDelayRecorder {
    private var validateCallCount = 0

    func recordValidation() {
        validateCallCount += 1
    }

    func snapshot() -> Int {
        validateCallCount
    }
}

actor ConcurrentGenerateRecorder {
    private var activeCount = 0
    private var maxActiveCount = 0

    func start() {
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
    }

    func finish() {
        activeCount = max(0, activeCount - 1)
    }

    func snapshot() -> Int {
        maxActiveCount
    }
}

struct RecordingProvider: ProviderAdapter {
    let recorder: DraftRequestRecorder

    func healthcheck() async -> Bool { true }

    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse {
        await recorder.record(input)

        let preview = String(input.rawText.prefix(120))
        let title: String
        switch input.generationMode {
        case .finalDocument:
            title = "Single Pass"
        case .chunkDigest:
            title = "Chunk Digest"
        case .mergedDocument:
            title = "Merged Draft"
        }

        return ProviderDraftResponse(
            title: title,
            summary: preview,
            keyPoints: [String(preview.prefix(60))],
            sections: [
                StructuredSection(title: title, body: preview, bulletPoints: [String(preview.prefix(40))])
            ],
            studyCards: [
                StudyCard(question: "What matters here?", answer: String(preview.prefix(80)))
            ],
            actionItems: [],
            reviewQuestions: [],
            renderedDocument: preview
        )
    }

    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        ProviderValidationResult(normalizedResponse: draft, warnings: [])
    }

    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? { nil }
}

struct WorkflowRecordingProvider: ProviderAdapter {
    let generateRecorder: DraftRequestRecorder?
    let validationRecorder: ValidationRecorder?
    let titlePrefix: String

    func healthcheck() async -> Bool { true }

    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse {
        if let generateRecorder {
            await generateRecorder.record(input)
        }

        let preview = String(input.rawText.prefix(120))
        return ProviderDraftResponse(
            title: "\(titlePrefix)-\(input.generationMode.rawValue)",
            summary: preview,
            keyPoints: [titlePrefix, String(preview.prefix(40))],
            sections: [
                StructuredSection(title: "\(titlePrefix) Section", body: preview, bulletPoints: [titlePrefix])
            ],
            studyCards: [StudyCard(question: "\(titlePrefix)?", answer: preview)],
            actionItems: [titlePrefix],
            reviewQuestions: [],
            renderedDocument: "\(titlePrefix): \(preview)"
        )
    }

    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        if let validationRecorder {
            await validationRecorder.record(draft)
        }

        var normalized = draft
        normalized.title = "\(titlePrefix)-validated"
        normalized.renderedDocument = "\(draft.renderedDocument)\n\nValidated by \(titlePrefix)"
        normalized.keyPoints.append("validated:\(titlePrefix)")
        return ProviderValidationResult(normalizedResponse: normalized, warnings: [])
    }

    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? { nil }
}

struct DelayedRecordingProvider: ProviderAdapter {
    let recorder: DraftRequestRecorder
    let concurrencyRecorder: ConcurrentGenerateRecorder
    let delayNanoseconds: UInt64

    func healthcheck() async -> Bool { true }

    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse {
        await concurrencyRecorder.start()
        do {
            try await Task.sleep(nanoseconds: delayNanoseconds)
            await recorder.record(input)

            let preview = String(input.rawText.prefix(120))
            let title: String
            switch input.generationMode {
            case .finalDocument:
                title = "Single Pass"
            case .chunkDigest:
                title = "Chunk Digest"
            case .mergedDocument:
                title = "Merged Draft"
            }

            let response = ProviderDraftResponse(
                title: title,
                summary: preview,
                keyPoints: [String(preview.prefix(60))],
                sections: [
                    StructuredSection(title: title, body: preview, bulletPoints: [String(preview.prefix(40))])
                ],
                studyCards: [
                    StudyCard(question: "What matters here?", answer: String(preview.prefix(80)))
                ],
                actionItems: [],
                reviewQuestions: [],
                renderedDocument: preview
            )

            await concurrencyRecorder.finish()
            return response
        } catch {
            await concurrencyRecorder.finish()
            throw error
        }
    }

    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        ProviderValidationResult(normalizedResponse: draft, warnings: [])
    }

    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? { nil }
}

struct DelayedValidationProvider: ProviderAdapter {
    let generateRecorder: DraftRequestRecorder?
    let validationRecorder: ValidationDelayRecorder
    let delayNanoseconds: UInt64
    let titlePrefix: String

    func healthcheck() async -> Bool { true }

    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse {
        if let generateRecorder {
            await generateRecorder.record(input)
        }

        let preview = String(input.rawText.prefix(120))
        return ProviderDraftResponse(
            title: "\(titlePrefix)-\(input.generationMode.rawValue)",
            summary: preview,
            keyPoints: [titlePrefix, String(preview.prefix(40))],
            sections: [
                StructuredSection(title: "\(titlePrefix) Section", body: preview, bulletPoints: [titlePrefix])
            ],
            studyCards: [StudyCard(question: "\(titlePrefix)?", answer: preview)],
            actionItems: [titlePrefix],
            reviewQuestions: [],
            renderedDocument: "\(titlePrefix): \(preview)"
        )
    }

    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        await validationRecorder.recordValidation()
        try await Task.sleep(nanoseconds: delayNanoseconds)

        var normalized = draft
        normalized.title = "\(titlePrefix)-validated"
        normalized.summary = "Refined summary from \(titlePrefix)"
        normalized.renderedDocument = "\(draft.renderedDocument)\n\nValidated by \(titlePrefix)"
        normalized.keyPoints.append("validated:\(titlePrefix)")
        return ProviderValidationResult(normalizedResponse: normalized, warnings: [])
    }

    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? { nil }
}

struct StubParser: IntakeParser {
    let parsed: ParsedDocument
    func parse(_ request: IntakeRequest) async throws -> ParsedDocument { parsed }
}
