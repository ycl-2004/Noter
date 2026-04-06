import Foundation
import Testing
@testable import NotesCurator

@MainActor
struct AppModelTests {
    @Test
    func appModelCreatesWorkspaceProcessesDraftAndRestoresLastSession() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "Marketing budget must be reduced and branding updated.",
                    sources: [
                        SourceReference(kind: .pastedText, title: "Input", excerpt: "Marketing budget...")
                    ],
                    images: []
                )
            ),
            primaryProvider: StubProvider(
                isHealthy: true,
                response: ProviderDraftResponse(
                    title: "Q3 Planning Note",
                    summary: "Budget and branding need follow-up.",
                    keyPoints: ["Budget down", "Brand refresh"],
                    sections: [StructuredSection(title: "Overview", body: "Need a follow-up plan.")],
                    actionItems: ["Share with finance"],
                    renderedDocument: "Summary\nBudget and branding need follow-up."
                )
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()

        let workspace = try await model.createWorkspace(named: "Strategy")
        #expect(model.selectedSidebarSection == .workspaces)
        #expect(model.selectedWorkspace?.id == workspace.id)

        try await model.processNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "Marketing budget must be reduced and branding updated.",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            )
        )

        #expect(model.workspaceItems(in: workspace.id, kind: .draft).count == 1)
        #expect(model.recentDrafts.count == 1)
        #expect(model.currentFlow == .editing)

        try await model.resumeLastSession()
        #expect(model.selectedWorkspace?.id == workspace.id)
        #expect(model.currentFlow == .editing)
    }

    @Test
    func appModelCanInsertSuggestedImagesAndSaveExplicitVersions() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "The roadmap depends on the chart in the attached image.",
                    sources: [
                        SourceReference(kind: .pastedText, title: "Input", excerpt: "The roadmap depends...")
                    ],
                    images: [
                        ParsedImageAsset(
                            title: "Launch Timeline",
                            summary: "A milestone chart for the next release.",
                            ocrText: "Phase 1, Beta, Launch"
                        )
                    ]
                )
            ),
            primaryProvider: StubProvider(
                isHealthy: true,
                response: ProviderDraftResponse(
                    title: "Roadmap Draft",
                    summary: "The release plan needs the timeline image.",
                    keyPoints: ["Keep the roadmap chart"],
                    sections: [StructuredSection(title: "Plan", body: "Review the attached timeline.")],
                    actionItems: ["Align milestones"],
                    renderedDocument: "Plan\nReview the attached timeline."
                )
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Roadmap")

        try await model.processNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "The roadmap depends on the chart in the attached image.",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            )
        )

        let originalVersionID = try #require(model.currentVersion?.id)
        let suggestionID = try #require(model.currentVersion?.imageSuggestions.first?.id)

        try await model.insertImageSuggestion(suggestionID)
        #expect(model.currentVersion?.editorDocument.contains("Launch Timeline") == true)
        #expect(model.currentVersion?.imageSuggestions.first?.isSelected == true)

        try await model.saveManualVersion()
        #expect(model.versions.count >= 2)
        #expect(model.currentVersion?.id != originalVersionID)
    }

    @Test
    func appModelReportsProviderHealth() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
            primaryProvider: StubProvider(isHealthy: true, response: .empty)
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        await model.refreshProviderStatus()

        #expect(model.providerStatusMessage == "Provider ready.")
    }

    @Test
    func appModelTracksWhetherALastSessionExists() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
            primaryProvider: StubProvider(isHealthy: true, response: .empty)
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        #expect(model.hasSavedSession == false)

        let workspace = try await model.createWorkspace(named: "Session Test")
        try await model.beginNewNote(in: workspace.id)
        #expect(model.hasSavedSession == true)
    }

    @Test
    func appModelUpdatesWorkspaceMetadata() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
            primaryProvider: StubProvider(isHealthy: true, response: .empty)
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Original")

        try await model.updateWorkspace(
            workspace.id,
            name: "Research Vault",
            subtitle: "Long-form notes and export presets for the active project.",
            cover: .graphite,
            coverImagePath: "/tmp/workspace-cover.png"
        )

        let updated = try #require(model.workspaces.first { $0.id == workspace.id })
        #expect(updated.name == "Research Vault")
        #expect(updated.subtitle == "Long-form notes and export presets for the active project.")
        #expect(updated.cover == .graphite)
        #expect(updated.coverImagePath == "/tmp/workspace-cover.png")
        #expect(repository.snapshot.workspaces.first { $0.id == workspace.id }?.name == "Research Vault")
    }

    @Test
    func appModelDeletesWorkspaceAndCascadesItsContent() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "Delete me",
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Delete me")],
                    images: []
                )
            ),
            primaryProvider: StubProvider(
                isHealthy: true,
                response: ProviderDraftResponse(
                    title: "Transient Draft",
                    summary: "Temporary content",
                    keyPoints: ["Temporary"],
                    sections: [StructuredSection(title: "Overview", body: "Temporary")],
                    actionItems: [],
                    renderedDocument: "Temporary"
                )
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()

        let workspace = try await model.createWorkspace(named: "Disposable")
        try await model.processNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "Delete me",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            )
        )

        #expect(model.workspaceItems(in: workspace.id, kind: .draft).count == 1)
        #expect(repository.snapshot.versions.count == 1)

        try await model.deleteWorkspace(workspace.id)

        #expect(model.workspaces.isEmpty)
        #expect(model.items.isEmpty)
        #expect(model.versions.isEmpty)
        #expect(repository.snapshot.workspaces.isEmpty)
        #expect(repository.snapshot.items.isEmpty)
        #expect(repository.snapshot.versions.isEmpty)
    }

    @Test
    func appModelCanUpdateVisualTemplateSelectionOnCurrentDraft() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "Theme me",
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Theme me")],
                    images: []
                )
            ),
            primaryProvider: StubProvider(
                isHealthy: true,
                response: ProviderDraftResponse(
                    title: "Theme Draft",
                    summary: "Needs a new theme.",
                    keyPoints: ["Theme"],
                    sections: [StructuredSection(title: "Overview", body: "Needs a new theme.")],
                    actionItems: [],
                    renderedDocument: "Needs a new theme."
                )
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Themes")

        try await model.processNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "Theme me",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            )
        )

        try await model.updateVisualTemplate("Graphite")

        #expect(model.currentVersion?.structuredDoc.exportMetadata.visualTemplateName == "Graphite")
        #expect(repository.snapshot.versions.last?.structuredDoc.exportMetadata.visualTemplateName == "Graphite")
    }

    @Test
    func appModelMigratesLegacyDefaultLocalOllamaPreferences() async throws {
        let repository = MemoryRepository()
        repository.snapshot.preferences = .legacyDefaultLocalOllama

        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
            primaryProvider: StubProvider(isHealthy: true, response: .empty)
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()

        #expect(model.preferences == .recommendedLocalOllama)
        #expect(repository.snapshot.preferences == .recommendedLocalOllama)
        #expect(model.preferences.providerKind == .localOllama)
        #expect(model.preferences.modelName == "qwen3:8b")
    }

    @Test
    func appModelPreservesIntentionalLocalOllamaConfiguration() async throws {
        let repository = MemoryRepository()
        repository.snapshot.preferences = AppPreferences(
            providerKind: .localOllama,
            modelName: "llama3.2:3b",
            defaultOutputLanguage: .english,
            defaultExportFormat: .pdf,
            autoSave: true,
            customBaseURL: "",
            customAPIKey: ""
        )

        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
            primaryProvider: StubProvider(isHealthy: true, response: .empty)
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()

        #expect(model.preferences.providerKind == .localOllama)
        #expect(model.preferences.modelName == "llama3.2:3b")
    }

    @Test
    func appModelMarksInterruptedProcessingDraftsAsFailedOnLoad() async throws {
        let repository = MemoryRepository()
        let workspace = Workspace(name: "Recovery", cover: .ocean)
        let staleDraft = WorkspaceItem(
            workspaceId: workspace.id,
            kind: .draft,
            title: "Interrupted Draft",
            summaryPreview: "Processing imported content...",
            status: .processing
        )
        repository.snapshot.workspaces = [workspace]
        repository.snapshot.items = [staleDraft]

        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
            primaryProvider: StubProvider(isHealthy: true, response: .empty)
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()

        let recoveredDraft = try #require(model.items.first)
        #expect(recoveredDraft.status == .failed)
        #expect(recoveredDraft.summaryPreview.contains("interrupted before completion"))
    }

    @Test
    func appPreferencesDefaultRecommendedModelUsesQwenThreeEightB() {
        #expect(AppPreferences.default.modelName == "qwen3:8b")
        #expect(AppPreferences.recommendedLocalOllama.modelName == "qwen3:8b")
    }

    @Test
    func appPreferencesExposeRecommendedNVIDIAHostedPreset() {
        #expect(AppPreferences.recommendedNVIDIAHosted.providerKind == .customAPI)
        #expect(AppPreferences.recommendedNVIDIAHosted.hostedService == .nvidia)
        #expect(AppPreferences.recommendedNVIDIAHosted.customBaseURL == "https://integrate.api.nvidia.com/v1")
        #expect(AppPreferences.recommendedNVIDIAHosted.modelName == "deepseek-ai/deepseek-v3.2")
        #expect(AppPreferences.recommendedNVIDIAHosted.enableWorkflowRouting == true)
        #expect(AppPreferences.recommendedNVIDIAHosted.customChunkModelName == "mistralai/mistral-small-3.1-24b-instruct-2503")
        #expect(AppPreferences.recommendedNVIDIAHosted.customPolishModelName == "mistralai/mistral-medium-3-instruct")
        #expect(AppPreferences.recommendedNVIDIAHosted.customRepairModelName == "qwen/qwen3-coder-480b-a35b-instruct")
        #expect(AppPreferences.recommendedNVIDIAHosted.customAPIKey.isEmpty)
    }

    @Test
    func appPreferencesExposeHostedPresetsByService() {
        let nvidiaPresets = AppPreferences.recommendedHostedPresetsByService[.nvidia] ?? []
        let geminiPresets = AppPreferences.recommendedHostedPresetsByService[.gemini] ?? []
        let zhipuPresets = AppPreferences.recommendedHostedPresetsByService[.zhipu] ?? []

        #expect(nvidiaPresets.count >= 4)
        #expect(nvidiaPresets.first?.modelName == "deepseek-ai/deepseek-v3.2")
        #expect(nvidiaPresets.allSatisfy { $0.baseURL == "https://integrate.api.nvidia.com/v1" })
        #expect(geminiPresets.contains(where: { $0.modelName == "gemini-2.5-flash" }))
        #expect(geminiPresets.allSatisfy { $0.service == .gemini })
        #expect(zhipuPresets.contains(where: { $0.modelName == "glm-4.7" }))
        #expect(zhipuPresets.contains(where: { $0.modelName == "glm-4.6v" }))
        #expect(zhipuPresets.contains(where: { $0.modelName == "glm-4.5-air" }))
        #expect(zhipuPresets.allSatisfy { $0.service == .zhipu })
    }

    @Test
    func appPreferencesInferHostedServiceFromBaseURL() throws {
        let json = """
        {
          "providerKind": "customAPI",
          "modelName": "claude-sonnet-4-20250514",
          "defaultOutputLanguage": "english",
          "defaultExportFormat": "pdf",
          "autoSave": true,
          "customBaseURL": "https://api.anthropic.com",
          "customAPIKey": "",
          "enableWorkflowRouting": true
        }
        """

        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))
        #expect(preferences.hostedService == .anthropic)
        #expect(preferences.customChunkModelName == HostedService.anthropic.recommendedChunkModel)
        #expect(preferences.customPolishModelName == HostedService.anthropic.recommendedPolishModel)
        #expect(preferences.customRepairModelName == HostedService.anthropic.recommendedRepairModel)
    }

    @Test
    func appModelCanStopAndDeleteProcessingDrafts() async throws {
        let repository = MemoryRepository()
        let parser = StubParser(
            parsed: ParsedDocument(
                text: "Slow processing test",
                sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Slow processing test")],
                images: []
            )
        )
        let cancellationRecorder = CancellationRecorder()
        let pipeline = DocumentProcessingPipeline(
            parser: parser,
            primaryProvider: SlowCancellableProvider(recorder: cancellationRecorder)
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Cancellation")

        try await model.startProcessingNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "Slow processing test",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            )
        )

        let processingDraft = try #require(model.workspaceItems(in: workspace.id, kind: .draft).first)
        #expect(processingDraft.status == .processing)

        try await model.stopAndDeleteDraft(processingDraft.id)

        #expect(model.workspaceItems(in: workspace.id, kind: .draft).isEmpty)
        #expect(await cancellationRecorder.cancelCallCount() == 1)
    }

    @Test
    func appModelPromotesInteractiveDraftBeforeBackgroundRefinementFinishes() async throws {
        let repository = MemoryRepository()
        let repairRecorder = ValidationDelayRecorder()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "This memo covers pricing, migration sequencing, and customer communication.",
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "This memo covers pricing...")],
                    images: []
                )
            ),
            primaryProvider: WorkflowRecordingProvider(
                generateRecorder: nil,
                validationRecorder: nil,
                titlePrefix: "draft"
            ),
            repairProvider: DelayedValidationProvider(
                generateRecorder: nil,
                validationRecorder: repairRecorder,
                delayNanoseconds: 300_000_000,
                titlePrefix: "repair"
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Background Refinement")

        try await model.startProcessingNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "This memo covers pricing, migration sequencing, and customer communication.",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            )
        )

        try await waitUntil {
            model.workspaceItems(in: workspace.id, kind: .draft).first?.status == .ready
        }

        let interactiveVersionID = try #require(model.currentVersion?.id)
        let readyDraft = try #require(model.workspaceItems(in: workspace.id, kind: .draft).first)
        #expect(readyDraft.refinementStatus == .refining)
        #expect(model.currentFlow == .editing)

        try await waitUntil {
            model.workspaceItems(in: workspace.id, kind: .draft).first?.refinementStatus == .refined
        }

        let refinedDraft = try #require(model.workspaceItems(in: workspace.id, kind: .draft).first)
        #expect(refinedDraft.pendingRefinedVersionId != nil)
        #expect(model.currentVersion?.id == interactiveVersionID)
        #expect(await repairRecorder.snapshot() == 1)

        try await model.applyPendingRefinedVersion()

        #expect(model.currentVersion?.id != interactiveVersionID)
        #expect(model.currentVersion?.origin == .refined)
        #expect(model.selectedDraftItem?.refinementStatus == DraftRefinementStatus.none)
        #expect(model.selectedDraftItem?.pendingRefinedVersionId == nil)
    }

    @Test
    func appModelCanDismissPendingRefinedVersion() async throws {
        let repository = MemoryRepository()
        let repairRecorder = ValidationDelayRecorder()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "This memo covers pricing, migration sequencing, and customer communication.",
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "This memo covers pricing...")],
                    images: []
                )
            ),
            primaryProvider: WorkflowRecordingProvider(
                generateRecorder: nil,
                validationRecorder: nil,
                titlePrefix: "draft"
            ),
            repairProvider: DelayedValidationProvider(
                generateRecorder: nil,
                validationRecorder: repairRecorder,
                delayNanoseconds: 200_000_000,
                titlePrefix: "repair"
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Dismiss Refinement")

        try await model.startProcessingNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "This memo covers pricing, migration sequencing, and customer communication.",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            )
        )

        try await waitUntil {
            model.workspaceItems(in: workspace.id, kind: .draft).first?.refinementStatus == .refined
        }

        let interactiveVersionID = try #require(model.currentVersion?.id)
        #expect(model.pendingRefinedVersion != nil)

        try await model.dismissPendingRefinedVersion()

        #expect(model.currentVersion?.id == interactiveVersionID)
        #expect(model.pendingRefinedVersion == nil)
        #expect(model.selectedDraftItem?.pendingRefinedVersionId == nil)
        #expect(model.selectedDraftItem?.refinementStatus == DraftRefinementStatus.none)
    }

    @Test
    func appModelMarksFailedDraftsAndAllowsDeletion() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(parsed: ParsedDocument(text: "Broken provider test", sources: [], images: [])),
            primaryProvider: ThrowingProvider(error: DocumentProcessingError.noHealthyProvider)
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Failures")

        do {
            try await model.processNewNote(
                in: workspace.id,
                intake: IntakeRequest(
                    pastedText: "Broken provider test",
                    fileURLs: [],
                    goalType: .structuredNotes,
                    outputLanguage: .english,
                    contentTemplateName: "Structured Notes",
                    visualTemplateName: "Oceanic Blue"
                )
            )
        } catch {
            #expect(error as? DocumentProcessingError == .noHealthyProvider)
        }

        let failedDraft = try #require(model.workspaceItems(in: workspace.id, kind: .draft).first)
        #expect(failedDraft.status == .failed)
        #expect(failedDraft.summaryPreview.contains("Processing failed."))
        #expect(model.currentFlow == .editing)

        try await model.deleteFailedDraft(failedDraft.id)
        #expect(model.workspaceItems(in: workspace.id, kind: .draft).isEmpty)
    }

    @Test
    func appModelSyncsSystemTemplatesAndRemovesRedundantVisualCopies() async throws {
        let repository = MemoryRepository()
        repository.snapshot.templates = [
            Template(kind: .visual, scope: .system, name: "Oceanic Blue", config: ["accent": "#165FCA", "surface": "#F6F9FF"]),
            Template(kind: .visual, scope: .user, name: "Oceanic Blue Copy", config: ["source": "Oceanic Blue"])
        ]

        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
            primaryProvider: StubProvider(isHealthy: true, response: .empty)
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()

        #expect(model.templates.contains { $0.name == "Indigo Ink" && $0.scope == .system })
        #expect(model.templates.contains { $0.name == "Emerald Grove" && $0.scope == .system })
        #expect(model.templates.contains { $0.name == "Oceanic Blue Copy" } == false)
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    intervalNanoseconds: UInt64 = 20_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
    while !condition() {
        if ContinuousClock.now >= deadline {
            Issue.record("Timed out waiting for condition to become true.")
            throw CancellationError()
        }
        try await Task.sleep(nanoseconds: intervalNanoseconds)
    }
}

private final class MemoryRepository: CuratorRepository, @unchecked Sendable {
    var snapshot = RepositorySnapshot.empty

    func save(workspace: Workspace) async throws { snapshot.workspaces = upsert(workspace, into: snapshot.workspaces) }
    func delete(workspaceID: UUID) async throws {
        let linkedItemIDs = Set(snapshot.items.filter { $0.workspaceId == workspaceID }.map(\.id))
        let linkedVersionIDs = Set(snapshot.versions.filter { linkedItemIDs.contains($0.workspaceItemId) }.map(\.id))
        snapshot.workspaces.removeAll { $0.id == workspaceID }
        snapshot.items.removeAll { linkedItemIDs.contains($0.id) }
        snapshot.versions.removeAll { linkedItemIDs.contains($0.workspaceItemId) }
        snapshot.exports.removeAll { linkedVersionIDs.contains($0.draftVersionId) }
    }
    func save(item: WorkspaceItem) async throws { snapshot.items = upsert(item, into: snapshot.items) }
    func save(version: DraftVersion) async throws { snapshot.versions = upsert(version, into: snapshot.versions) }
    func save(template: Template) async throws { snapshot.templates = upsert(template, into: snapshot.templates) }
    func delete(templateID: UUID) async throws { snapshot.templates.removeAll { $0.id == templateID } }
    func save(export: ExportRecord) async throws { snapshot.exports = upsert(export, into: snapshot.exports) }
    func delete(itemID: UUID) async throws {
        snapshot.items.removeAll { $0.id == itemID }
        snapshot.versions.removeAll { $0.workspaceItemId == itemID }
    }
    func save(preferences: AppPreferences) async throws { snapshot.preferences = preferences }
    func save(lastSession: LastSessionSnapshot) async throws { snapshot.lastSession = lastSession }
    func loadSnapshot() async throws -> RepositorySnapshot { snapshot }

    private func upsert<T: Identifiable & Equatable>(_ value: T, into values: [T]) -> [T] {
        let filtered = values.filter { $0.id != value.id }
        return filtered + [value]
    }
}

private struct ThrowingProvider: ProviderAdapter {
    let error: DocumentProcessingError

    func healthcheck() async -> Bool { false }
    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse { throw error }
    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        throw error
    }
    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? {
        throw error
    }
}

private actor CancellationRecorder {
    private var cancelCalls = 0

    func recordCancel() {
        cancelCalls += 1
    }

    func cancelCallCount() -> Int {
        cancelCalls
    }
}

private struct SlowCancellableProvider: ProviderAdapter {
    let recorder: CancellationRecorder

    func healthcheck() async -> Bool { true }

    func generateStructuredDraft(input: ProviderDraftRequest) async throws -> ProviderDraftResponse {
        try await Task.sleep(for: .seconds(5))
        return ProviderDraftResponse(
            title: "Slow Draft",
            summary: "Slow Draft",
            keyPoints: ["Slow Draft"],
            sections: [StructuredSection(title: "Overview", body: "Slow Draft")],
            actionItems: [],
            renderedDocument: "Slow Draft"
        )
    }

    func validateDraft(draft: ProviderDraftResponse, sourceText: String) async throws -> ProviderValidationResult {
        ProviderValidationResult(normalizedResponse: draft, warnings: [])
    }

    func analyzeImage(_ image: ParsedImageAsset, context: String) async throws -> ImageSuggestion? { nil }

    func cancelActiveWork() async {
        await recorder.recordCancel()
    }
}
