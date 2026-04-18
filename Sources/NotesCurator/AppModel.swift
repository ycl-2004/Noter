import Foundation
import Observation

enum WorkspaceFlowStage: String, Equatable, Sendable {
    case intake
    case processing
    case editing
    case preview
    case export
}

@MainActor
@Observable
final class NotesCuratorAppModel {
    private let repository: CuratorRepository
    private var pipeline: DocumentProcessingPipeline
    private let pipelineBuilder: ((AppPreferences) -> DocumentProcessingPipeline)?
    private var processingTasks: [UUID: Task<Void, Never>] = [:]
    private var refinementTasks: [UUID: Task<Void, Never>] = [:]
    private var deletedItemIDs: Set<UUID> = []

    var selectedSidebarSection: SidebarSection = .home
    var workspaces: [Workspace] = []
    var items: [WorkspaceItem] = []
    var versions: [DraftVersion] = []
    var templates: [Template] = []
    var exports: [ExportRecord] = []
    var preferences: AppPreferences = .default
    var selectedWorkspaceID: UUID?
    var selectedItemID: UUID?
    var currentFlow: WorkspaceFlowStage?
    var processingStages: [ProcessingStage] = []
    var processingStartedAt: Date?
    var currentProcessingStageStartedAt: Date?
    var lastErrorMessage: String?
    var providerStatusMessage: String?
    var providerStatusDetail: String?
    var hasSavedSession = false
    var pendingContentTemplateName: String?
    var pendingVisualTemplateName: String?
    var pendingTemplateImportReview: TemplateImportReview?
    var editingTemplatePack: TemplatePack?

    init(
        repository: CuratorRepository,
        pipeline: DocumentProcessingPipeline,
        pipelineBuilder: ((AppPreferences) -> DocumentProcessingPipeline)? = nil
    ) {
        self.repository = repository
        self.pipeline = pipeline
        self.pipelineBuilder = pipelineBuilder
    }

    var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    var recentDrafts: [WorkspaceItem] {
        items
            .filter { $0.kind == .draft }
            .sorted { $0.lastEditedAt > $1.lastEditedAt }
            .prefix(5)
            .map { $0 }
    }

    var currentVersion: DraftVersion? {
        guard let selectedItem = items.first(where: { $0.id == selectedItemID }),
              let versionID = selectedItem.currentVersionId else {
            return nil
        }
        return versions.first(where: { $0.id == versionID })
    }

    var selectedDraftItem: WorkspaceItem? {
        items.first { $0.id == selectedItemID }
    }

    var pendingRefinedVersion: DraftVersion? {
        guard let pendingID = selectedDraftItem?.pendingRefinedVersionId else {
            return nil
        }
        return versions.first(where: { $0.id == pendingID })
    }

    var contentTemplates: [Template] {
        effectiveTemplates(of: .content)
    }

    var visualTemplates: [Template] {
        effectiveTemplates(of: .visual)
    }

    func load() async throws {
        let snapshot = try await repository.loadSnapshot()
        apply(snapshot)
        try await recoverInterruptedProcessingDraftsIfNeeded()
        try await migrateLegacyDefaultPreferencesIfNeeded()
        try await syncSystemTemplatesIfNeeded()
        try await removeRedundantTemplateCopiesIfNeeded()
    }

    @discardableResult
    func createWorkspace(named name: String) async throws -> Workspace {
        let workspace = Workspace(name: name, cover: .ocean, pinned: workspaces.isEmpty)
        try await repository.save(workspace: workspace)
        workspaces.insert(workspace, at: 0)
        selectedSidebarSection = .workspaces
        selectedWorkspaceID = workspace.id
        try await persistLastSession(
            LastSessionSnapshot(sidebarSection: .workspaces, workspaceId: workspace.id, itemId: nil)
        )
        return workspace
    }

    func beginNewNote(in workspaceID: UUID?) async throws {
        let resolvedWorkspaceID: UUID
        if let workspaceID {
            resolvedWorkspaceID = workspaceID
        } else if let firstWorkspace = workspaces.first {
            resolvedWorkspaceID = firstWorkspace.id
        } else {
            resolvedWorkspaceID = try await createWorkspace(named: "Personal Workspace").id
        }

        selectedSidebarSection = .workspaces
        selectedWorkspaceID = resolvedWorkspaceID
        selectedItemID = nil
        currentFlow = .intake
        try await persistLastSession(
            LastSessionSnapshot(sidebarSection: .workspaces, workspaceId: resolvedWorkspaceID, itemId: nil)
        )
    }

    func updateWorkspace(
        _ workspaceID: UUID,
        name: String,
        subtitle: String,
        cover: WorkspaceCover,
        coverImagePath: String?
    ) async throws {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        workspaces[index].name = name
        workspaces[index].subtitle = subtitle
        workspaces[index].cover = cover
        workspaces[index].coverImagePath = coverImagePath
        workspaces[index].updatedAt = .now
        let updated = workspaces[index]
        try await repository.save(workspace: updated)
    }

    func deleteWorkspace(_ workspaceID: UUID) async throws {
        let workspaceItemIDs = Set(items.filter { $0.workspaceId == workspaceID }.map(\.id))
        let workspaceVersionIDs = Set(
            versions
                .filter { workspaceItemIDs.contains($0.workspaceItemId) }
                .map(\.id)
        )
        deletedItemIDs.formUnion(workspaceItemIDs)

        for itemID in workspaceItemIDs {
            if items.first(where: { $0.id == itemID })?.status == .processing {
                processingTasks[itemID]?.cancel()
                processingTasks[itemID] = nil
            }
            refinementTasks[itemID]?.cancel()
            refinementTasks[itemID] = nil
        }

        if processingTasks.isEmpty && refinementTasks.isEmpty {
            await pipeline.cancelActiveWork()
        }

        try await repository.delete(workspaceID: workspaceID)

        workspaces.removeAll { $0.id == workspaceID }
        items.removeAll { workspaceItemIDs.contains($0.id) }
        versions.removeAll { workspaceItemIDs.contains($0.workspaceItemId) }
        exports.removeAll { workspaceVersionIDs.contains($0.draftVersionId) }

        let nextWorkspaceID = workspaces.sorted { $0.updatedAt > $1.updatedAt }.first?.id
        if selectedWorkspaceID == workspaceID {
            selectedWorkspaceID = nextWorkspaceID
        }
        if let selectedItemID, workspaceItemIDs.contains(selectedItemID) {
            self.selectedItemID = nil
            currentFlow = nil
            processingStages = []
            processingStartedAt = nil
            currentProcessingStageStartedAt = nil
        }

        selectedSidebarSection = .workspaces
        hasSavedSession = selectedWorkspaceID != nil || selectedItemID != nil
        try await persistLastSession(
            LastSessionSnapshot(
                sidebarSection: .workspaces,
                workspaceId: selectedWorkspaceID,
                itemId: selectedItemID
            )
        )
    }

    func openWorkspace(_ workspaceID: UUID) async throws {
        selectedSidebarSection = .workspaces
        selectedWorkspaceID = workspaceID
        currentFlow = nil
        try await persistLastSession(
            LastSessionSnapshot(sidebarSection: .workspaces, workspaceId: workspaceID, itemId: nil)
        )
    }

    func workspaceItems(in workspaceID: UUID, kind: WorkspaceItemKind) -> [WorkspaceItem] {
        items
            .filter { $0.workspaceId == workspaceID && $0.kind == kind }
            .sorted { $0.lastEditedAt > $1.lastEditedAt }
    }

    func processNewNote(in workspaceID: UUID, intake: IntakeRequest) async throws {
        try await runProcessingNote(in: workspaceID, intake: intake)
    }

    func startProcessingNewNote(in workspaceID: UUID, intake: IntakeRequest) async throws {
        let item = try await prepareDraftForProcessing(in: workspaceID)

        let task = Task { @MainActor [self] in
            defer { processingTasks[item.id] = nil }
            do {
                try await runPreparedProcessingNote(item: item, intake: intake, workspaceID: workspaceID)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                do {
                    try await markProcessingFailed(for: item, workspaceID: workspaceID, error: error)
                } catch {
                    present(error: error)
                }
            }
        }

        processingTasks[item.id] = task
    }

    func openDraft(_ itemID: UUID) async throws {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        selectedSidebarSection = .workspaces
        selectedWorkspaceID = item.workspaceId
        selectedItemID = itemID
        switch item.status {
        case .processing:
            currentFlow = .processing
        case .ready, .failed:
            currentFlow = .editing
        }
        try await persistLastSession(
            LastSessionSnapshot(sidebarSection: .workspaces, workspaceId: item.workspaceId, itemId: itemID)
        )
    }

    func deleteFailedDraft(_ itemID: UUID) async throws {
        guard let item = items.first(where: { $0.id == itemID && $0.status == .failed }) else { return }
        try await deleteWorkspaceItem(item.id)
    }

    func stopAndDeleteDraft(_ itemID: UUID) async throws {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        try await deleteWorkspaceItem(item.id)
    }

    func deleteWorkspaceItem(_ itemID: UUID) async throws {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        deletedItemIDs.insert(itemID)

        if item.status == .processing {
            processingTasks[itemID]?.cancel()
            processingTasks[itemID] = nil
        }
        refinementTasks[itemID]?.cancel()
        refinementTasks[itemID] = nil
        if processingTasks.isEmpty && refinementTasks.isEmpty {
            await pipeline.cancelActiveWork()
        }

        let linkedVersionIDs = Set(
            versions
                .filter { $0.workspaceItemId == itemID }
                .map(\.id)
        )
        let exportVersionIDs = exportVersionIDs(for: item, linkedVersionIDs: linkedVersionIDs)
        let linkedExportItemIDs = linkedExportItemIDs(for: exportVersionIDs, excluding: itemID)

        try await repository.delete(itemID: itemID)
        items.removeAll { $0.id == itemID || linkedExportItemIDs.contains($0.id) }
        versions.removeAll { $0.workspaceItemId == itemID }
        exports.removeAll { exportVersionIDs.contains($0.draftVersionId) }

        if let selectedItemID, selectedItemID == itemID || linkedExportItemIDs.contains(selectedItemID) {
            self.selectedItemID = nil
            currentFlow = nil
            processingStages = []
            processingStartedAt = nil
            currentProcessingStageStartedAt = nil
        }

        hasSavedSession = selectedWorkspaceID != nil || self.selectedItemID != nil
        try await persistLastSession(
            LastSessionSnapshot(
                sidebarSection: selectedSidebarSection,
                workspaceId: selectedWorkspaceID ?? item.workspaceId,
                itemId: selectedItemID
            )
        )
    }

    func clearStuckDrafts() async throws {
        let stuckItems = items.filter {
            $0.kind == .draft && ($0.status == .processing || $0.status == .failed)
        }
        guard !stuckItems.isEmpty else { return }
        deletedItemIDs.formUnion(stuckItems.map(\.id))

        for item in stuckItems where item.status == .processing {
            processingTasks[item.id]?.cancel()
            processingTasks[item.id] = nil
        }
        if stuckItems.contains(where: { $0.status == .processing }) && processingTasks.isEmpty {
            await pipeline.cancelActiveWork()
        }

        let itemIDs = Set(stuckItems.map(\.id))
        for itemID in itemIDs {
            try await repository.delete(itemID: itemID)
        }

        items.removeAll { itemIDs.contains($0.id) }
        versions.removeAll { itemIDs.contains($0.workspaceItemId) }

        if let selectedItemID, itemIDs.contains(selectedItemID) {
            self.selectedItemID = nil
            currentFlow = nil
            processingStages = []
            processingStartedAt = nil
            currentProcessingStageStartedAt = nil
        }

        try await persistLastSession(
            LastSessionSnapshot(
                sidebarSection: selectedSidebarSection,
                workspaceId: selectedWorkspaceID,
                itemId: selectedItemID
            )
        )
    }

    func updateEditorDocument(_ document: String) async throws {
        guard var version = currentVersion else { return }
        version.editorDocument = document
        version.structuredDoc = EditorDocumentSync.sync(
            document: document,
            into: version.structuredDoc,
            language: version.outputLanguage
        )
        try await persistCurrentVersion(version)
        try await syncSelectedDraftItem(using: version)
    }

    func updateVisualTemplate(_ name: String) async throws {
        guard var version = currentVersion else { return }
        version.structuredDoc.exportMetadata.visualTemplateName = name
        version.structuredDoc.exportMetadata.visualTemplateID = visualTemplate(named: name)?.id
        try await persistCurrentVersion(version)
    }

    func updateSelectedContentTemplate(_ templateID: UUID) async throws {
        guard var version = currentVersion,
              let template = contentTemplate(id: templateID) else {
            return
        }

        version.structuredDoc.exportMetadata.contentTemplateID = template.id
        version.structuredDoc.exportMetadata.contentTemplateName = template.name
        version.structuredDoc.exportMetadata.contentTemplatePackData = template.storedPackData
        version.structuredDoc.exportMetadata.contentTemplateLatexProjectData = template.storedLatexProjectData
        try await persistCurrentVersion(version)
    }

    func regenerateCurrentDraftWithSelectedTemplate() async throws {
        guard let version = currentVersion,
              let sourceText = version.generationSourceText,
              let contentTemplate = resolvedContentTemplate(for: version) else {
            return
        }

        let visualTemplate = resolvedVisualTemplate(for: version)
        let regenerated = try await refreshedPipeline().regenerateDraft(
            sourceText: sourceText,
            workspaceItemId: version.workspaceItemId,
            goalType: version.goalType,
            outputLanguage: version.outputLanguage,
            sourceRefs: version.sourceRefs,
            imageSuggestions: version.imageSuggestions,
            contentTemplate: contentTemplate,
            visualTemplate: visualTemplate,
            contentTemplateName: version.structuredDoc.exportMetadata.contentTemplateName,
            visualTemplateName: version.structuredDoc.exportMetadata.visualTemplateName
        )

        let updatedVersion = DraftVersion(
            id: version.id,
            workspaceItemId: version.workspaceItemId,
            goalType: regenerated.goalType,
            outputLanguage: regenerated.outputLanguage,
            editorDocument: regenerated.editorDocument,
            structuredDoc: regenerated.structuredDoc,
            sourceRefs: regenerated.sourceRefs,
            imageSuggestions: regenerated.imageSuggestions,
            origin: version.origin,
            parentVersionId: version.parentVersionId,
            createdAt: version.createdAt,
            generationSourceText: sourceText
        )

        try await persistCurrentVersion(updatedVersion)
        try await syncSelectedDraftItem(using: updatedVersion)
    }

    func insertImageSuggestion(_ suggestionID: UUID) async throws {
        guard var version = currentVersion,
              let suggestionIndex = version.imageSuggestions.firstIndex(where: { $0.id == suggestionID }) else {
            return
        }

        version.imageSuggestions[suggestionIndex].isSelected = true
        let suggestion = version.imageSuggestions[suggestionIndex]
        let insertion = imageInsertionBlock(for: suggestion, language: version.outputLanguage)
        if !version.editorDocument.contains(suggestion.title) {
            let separator = version.editorDocument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            version.editorDocument += separator + insertion
        }
        if !version.structuredDoc.imageSlots.contains(where: { $0.suggestionID == suggestionID }) {
            version.structuredDoc.imageSlots.append(ImageSlot(suggestionID: suggestionID, caption: suggestion.title))
        }

        try await persistCurrentVersion(version)
        try await syncSelectedDraftItem(using: version)
    }

    func saveManualVersion() async throws {
        guard let currentVersion, var currentItem = selectedDraftItem else { return }

        let savedVersion = DraftVersion(
            workspaceItemId: currentVersion.workspaceItemId,
            goalType: currentVersion.goalType,
            outputLanguage: currentVersion.outputLanguage,
            editorDocument: currentVersion.editorDocument,
            structuredDoc: currentVersion.structuredDoc,
            sourceRefs: currentVersion.sourceRefs,
            imageSuggestions: currentVersion.imageSuggestions,
            origin: .manual,
            parentVersionId: currentVersion.id,
            generationSourceText: currentVersion.generationSourceText
        )

        try await repository.save(version: savedVersion)
        versions.insert(savedVersion, at: 0)

        currentItem.currentVersionId = savedVersion.id
        currentItem.title = savedVersion.structuredDoc.title
        currentItem.lastEditedAt = .now
        currentItem.summaryPreview = summaryPreview(for: savedVersion.editorDocument, fallback: savedVersion.structuredDoc.summary)
        currentItem.status = .ready
        try await persistWorkspaceItem(currentItem)

        try await persistLastSession(
            LastSessionSnapshot(
                sidebarSection: .workspaces,
                workspaceId: currentItem.workspaceId,
                itemId: currentItem.id
            )
        )
    }

    func showPreview() {
        currentFlow = .preview
    }

    func showExport() {
        currentFlow = .export
    }

    func goBackToEditing() {
        currentFlow = .editing
    }

    func openSettings() {
        selectedSidebarSection = .settings
        currentFlow = nil
    }

    func showWorkspaceOverview() async throws {
        guard let workspaceID = selectedWorkspaceID else { return }
        selectedItemID = nil
        currentFlow = nil
        processingStages = []
        processingStartedAt = nil
        currentProcessingStageStartedAt = nil
        try await persistLastSession(
            LastSessionSnapshot(sidebarSection: .workspaces, workspaceId: workspaceID, itemId: nil)
        )
    }

    @discardableResult
    func exportCurrentDraft(
        format: ExportFormat,
        visualTemplateName: String? = nil,
        to outputDirectory: URL
    ) async throws -> URL? {
        guard let version = currentVersion, let item = selectedDraftItem else { return nil }
        let coordinator = ExportCoordinator()
        var exportVersion = version
        if let visualTemplateName {
            exportVersion.structuredDoc.exportMetadata.visualTemplateName = visualTemplateName
            exportVersion.structuredDoc.exportMetadata.visualTemplateID = visualTemplate(named: visualTemplateName)?.id
            try await persistCurrentVersion(exportVersion)
        }

        let url = try coordinator.export(draft: exportVersion, format: format, to: outputDirectory)

        let record = ExportRecord(draftVersionId: exportVersion.id, format: format, outputPath: url.path)
        try await repository.save(export: record)
        exports.insert(record, at: 0)

        let exportItem = WorkspaceItem(
            workspaceId: item.workspaceId,
            kind: .export,
            title: url.lastPathComponent,
            summaryPreview: "Exported \(format.rawValue.uppercased()) file",
            currentVersionId: exportVersion.id
        )
        try await repository.save(item: exportItem)
        items.insert(exportItem, at: 0)
        return url
    }

    func deleteExportRecord(_ exportID: UUID) async throws {
        guard exports.contains(where: { $0.id == exportID }) else { return }
        try await repository.delete(exportID: exportID)
        exports.removeAll { $0.id == exportID }
    }

    func saveUserTemplate(
        kind: TemplateKind,
        name: String,
        subtitle: String = "",
        templateDescription: String = "",
        format: TemplateFormat = .legacyConfig,
        body: String = "",
        config: [String: String]
    ) async throws {
        let template = Template(
            kind: kind,
            scope: .user,
            name: name,
            subtitle: subtitle,
            templateDescription: templateDescription,
            format: format,
            body: body,
            config: config
        )
        try await saveTemplate(template)
    }

    func saveTemplate(_ template: Template) async throws {
        try await repository.save(template: template)
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        sortTemplates()
    }

    func beginLatexTemplateImport(_ source: String) throws {
        let review = try LatexTemplateImporter.importTemplate(from: source)
        pendingTemplateImportReview = review
        editingTemplatePack = review.templatePack
    }

    func beginLatexTemplateProjectImport(_ url: URL) throws {
        let review = try LatexProjectTemplateImporter.importTemplateProject(from: url)
        pendingTemplateImportReview = review
        editingTemplatePack = review.templatePack
    }

    func adjustPendingImportArchetype(_ archetype: TemplateArchetype) {
        pendingTemplateImportReview = pendingTemplateImportReview?.rebuild(for: archetype)
        editingTemplatePack = pendingTemplateImportReview?.templatePack
    }

    @discardableResult
    func savePendingTemplateImport(as scope: TemplateScope = .user) async throws -> Template? {
        guard let review = pendingTemplateImportReview else { return nil }
        let pack = editingTemplatePack ?? review.templatePack
        let goalType: GoalType
        switch pack.archetype {
        case .meetingBrief:
            goalType = .actionItems
        case .formalBrief:
            goalType = .formalDocument
        case .technicalNote:
            goalType = .structuredNotes
        }
        let template: Template
        if let projectSource = review.latexProjectSource {
            template = Template.latexProject(
                projectSource,
                scope: scope,
                name: pack.identity.name,
                subtitle: pack.identity.description,
                templateDescription: pack.identity.description.isEmpty ? "Imported from LaTeX project" : pack.identity.description,
                goalType: goalType,
                pack: pack
            )
        } else {
            template = Template.packBacked(
                pack,
                scope: scope,
                goalType: goalType,
                templateDescription: pack.identity.description.isEmpty ? "Imported from LaTeX" : pack.identity.description,
                latexSource: review.source
            )
        }
        try await saveTemplate(template)
        pendingTemplateImportReview = nil
        editingTemplatePack = nil
        return template
    }

    func discardPendingTemplateImport() {
        pendingTemplateImportReview = nil
        editingTemplatePack = nil
    }

    func beginEditingTemplatePack(_ template: Template) throws {
        editingTemplatePack = try template.templatePack()
    }

    func moveEditingTemplateBlock(from source: Int, to destination: Int) {
        guard var pack = editingTemplatePack,
              pack.layout.blocks.indices.contains(source) else {
            return
        }

        let block = pack.layout.blocks.remove(at: source)
        let targetIndex = max(0, min(destination, pack.layout.blocks.count))
        pack.layout.blocks.insert(block, at: targetIndex)
        editingTemplatePack = pack
        syncEditingPackIntoPendingImport()
    }

    func renameEditingTemplateBlock(_ blockID: UUID, to title: String) {
        guard var pack = editingTemplatePack,
              let index = pack.layout.blocks.firstIndex(where: { $0.id == blockID }) else {
            return
        }

        pack.layout.blocks[index].titleOverride = title.trimmingCharacters(in: .whitespacesAndNewlines)
        editingTemplatePack = pack
        syncEditingPackIntoPendingImport()
    }

    func setEditingTemplateEmptyBehavior(
        _ blockID: UUID,
        authoring: EmptyBlockBehavior,
        preview: EmptyBlockBehavior,
        export: EmptyBlockBehavior
    ) {
        guard var pack = editingTemplatePack,
              let index = pack.layout.blocks.firstIndex(where: { $0.id == blockID }) else {
            return
        }

        pack.layout.blocks[index].emptyBehavior = SurfaceEmptyBehavior(
            authoring: authoring,
            preview: preview,
            export: export
        )
        editingTemplatePack = pack
        syncEditingPackIntoPendingImport()
    }

    @discardableResult
    func saveEditingTemplatePack(as scope: TemplateScope = .user) async throws -> Template? {
        guard let pack = editingTemplatePack else { return nil }
        let template = Template.packBacked(pack, scope: scope)
        try await saveTemplate(template)
        return template
    }

    @discardableResult
    func duplicateTemplate(_ templateID: UUID) async throws -> Template? {
        guard let template = templates.first(where: { $0.id == templateID }) else { return nil }
        let duplicate = template.duplicated(named: "\(template.name) Copy")
        try await saveTemplate(duplicate)
        return duplicate
    }

    func deleteTemplate(_ templateID: UUID) async throws {
        guard let template = templates.first(where: { $0.id == templateID }),
              template.scope == .user else {
            return
        }
        try await repository.delete(templateID: templateID)
        templates.removeAll { $0.id == templateID }
    }

    func startNewNote(using template: Template) async throws {
        if template.kind == .content {
            pendingContentTemplateName = template.name
        } else {
            pendingVisualTemplateName = template.name
        }
        try await beginNewNote(in: selectedWorkspaceID)
    }

    func resumeLastSession() async throws {
        let snapshot = try await repository.loadSnapshot()
        apply(snapshot)
        guard let lastSession = snapshot.lastSession else { return }
        selectedSidebarSection = lastSession.sidebarSection
        selectedWorkspaceID = lastSession.workspaceId
        selectedItemID = lastSession.itemId
        currentFlow = lastSession.itemId == nil ? nil : .editing
    }

    func updatePreferences(_ mutate: (inout AppPreferences) -> Void) async throws {
        mutate(&preferences)
        try await repository.save(preferences: preferences)
        if let pipelineBuilder {
            pipeline = pipelineBuilder(preferences)
        }
    }

    func refreshProviderStatus(using preferencesOverride: AppPreferences? = nil) async {
        let resolvedPreferences = preferencesOverride ?? preferences
        let pipelineToInspect = pipelineBuilder?(resolvedPreferences) ?? pipeline

        if preferencesOverride == nil, let pipelineBuilder {
            pipeline = pipelineBuilder(preferences)
        }

        let health = await pipelineToInspect.providerHealthStatus()
        providerStatusMessage = health.summary
        providerStatusDetail = health.detail
    }

    func present(error: Error) {
        lastErrorMessage = userFacingMessage(for: error)
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private func apply(_ snapshot: RepositorySnapshot) {
        workspaces = snapshot.workspaces
        items = snapshot.items
        versions = snapshot.versions
        templates = snapshot.templates
        exports = snapshot.exports
        preferences = snapshot.preferences
        hasSavedSession = snapshot.lastSession?.workspaceId != nil || snapshot.lastSession?.itemId != nil
        if let pipelineBuilder {
            pipeline = pipelineBuilder(snapshot.preferences)
        }
    }

    private func migrateLegacyDefaultPreferencesIfNeeded() async throws {
        guard let migratedPreferences = preferences.legacyMigrationTarget else { return }
        preferences = migratedPreferences
        try await repository.save(preferences: preferences)
        if let pipelineBuilder {
            pipeline = pipelineBuilder(preferences)
        }
    }

    private func recoverInterruptedProcessingDraftsIfNeeded() async throws {
        let staleDraftIDs = Set(
            items
                .filter { $0.kind == .draft && $0.status == .processing }
                .map(\.id)
        )
        guard !staleDraftIDs.isEmpty else { return }

        await pipeline.cancelActiveWork()

        for index in items.indices where staleDraftIDs.contains(items[index].id) {
            items[index].status = .failed
            items[index].summaryPreview = interruptedSummary(for: items[index].summaryPreview)
            items[index].lastEditedAt = .now
            try await repository.save(item: items[index])
        }
    }

    private func refreshedPipeline() -> DocumentProcessingPipeline {
        if let pipelineBuilder {
            let updatedPipeline = pipelineBuilder(preferences)
            pipeline = updatedPipeline
            return updatedPipeline
        }
        return pipeline
    }

    private func runProcessingNote(in workspaceID: UUID, intake: IntakeRequest) async throws {
        let item = try await prepareDraftForProcessing(in: workspaceID)
        do {
            try await runPreparedProcessingNote(item: item, intake: intake, workspaceID: workspaceID)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else {
                throw error
            }
            try? await markProcessingFailed(for: item, workspaceID: workspaceID, error: error)
            throw error
        }
    }

    private func runPreparedProcessingNote(
        item: WorkspaceItem,
        intake: IntakeRequest,
        workspaceID: UUID
    ) async throws {
        let pipelineForRequest = refreshedPipeline()
        let result = try await pipelineForRequest.processInteractive(
            intake: intake,
            workspaceItemId: item.id,
            contentTemplate: resolvedContentTemplate(named: intake.contentTemplateName, goalType: intake.goalType),
            visualTemplate: visualTemplate(named: intake.visualTemplateName),
            onStageChange: { [weak self] stage in
                Task { @MainActor in
                    self?.processingStages.append(stage)
                    self?.currentProcessingStageStartedAt = .now
                }
            }
        )
        try Task.checkCancellation()
        try await completeInteractiveProcessing(item: item, result: result, workspaceID: workspaceID)
    }

    private func prepareDraftForProcessing(in workspaceID: UUID) async throws -> WorkspaceItem {
        processingStages = []
        processingStartedAt = .now
        currentProcessingStageStartedAt = .now
        selectedSidebarSection = .workspaces
        selectedWorkspaceID = workspaceID
        currentFlow = .processing

        let item = WorkspaceItem(
            workspaceId: workspaceID,
            kind: .draft,
            title: "Untitled Draft",
            summaryPreview: "Processing imported content...",
            currentVersionId: nil,
            status: .processing
        )
        try await repository.save(item: item)
        items.insert(item, at: 0)
        selectedItemID = item.id
        try await persistLastSession(
            LastSessionSnapshot(sidebarSection: .workspaces, workspaceId: workspaceID, itemId: item.id)
        )
        return item
    }

    func applyPendingRefinedVersion() async throws {
        guard var item = selectedDraftItem,
              let pendingVersion = pendingRefinedVersion else { return }

        item.currentVersionId = pendingVersion.id
        item.title = pendingVersion.structuredDoc.title
        item.pendingRefinedVersionId = nil
        item.refinementStatus = .none
        item.lastEditedAt = .now
        item.summaryPreview = summaryPreview(for: pendingVersion.editorDocument, fallback: pendingVersion.structuredDoc.summary)
        try await persistWorkspaceItem(item)
    }

    func dismissPendingRefinedVersion() async throws {
        guard var item = selectedDraftItem else { return }
        item.pendingRefinedVersionId = nil
        item.refinementStatus = .none
        item.lastEditedAt = .now
        try await persistWorkspaceItem(item)
    }

    private func completeInteractiveProcessing(
        item: WorkspaceItem,
        result: InteractiveDraftResult,
        workspaceID: UUID
    ) async throws {
        try await repository.save(version: result.version)
        versions.insert(result.version, at: 0)

        var updatedItem = item
        updatedItem.title = result.version.structuredDoc.title
        updatedItem.summaryPreview = result.version.structuredDoc.summary
        updatedItem.lastEditedAt = .now
        updatedItem.currentVersionId = result.version.id
        updatedItem.status = .ready
        updatedItem.refinementStatus = result.shouldRefineInBackground ? .refining : .none
        updatedItem.pendingRefinedVersionId = nil
        try await persistWorkspaceItem(updatedItem)

        currentProcessingStageStartedAt = nil
        currentFlow = .editing
        try await persistLastSession(
            LastSessionSnapshot(sidebarSection: .workspaces, workspaceId: workspaceID, itemId: item.id)
        )

        if result.shouldRefineInBackground {
            startBackgroundRefinement(
                for: updatedItem,
                baseVersion: result.version,
                sourceText: result.sourceText
            )
        }
    }

    private func markProcessingFailed(
        for item: WorkspaceItem,
        workspaceID: UUID,
        error: Error
    ) async throws {
        var updatedItem = item
        updatedItem.lastEditedAt = .now
        updatedItem.summaryPreview = failureSummary(for: error)
        updatedItem.status = .failed
        updatedItem.refinementStatus = .none
        updatedItem.pendingRefinedVersionId = nil
        try await persistWorkspaceItem(updatedItem)
        currentProcessingStageStartedAt = nil
        currentFlow = .editing
        try await persistLastSession(
            LastSessionSnapshot(sidebarSection: .workspaces, workspaceId: workspaceID, itemId: item.id)
        )
    }

    private func persistCurrentVersion(_ version: DraftVersion) async throws {
        try await repository.save(version: version)
        if let index = versions.firstIndex(where: { $0.id == version.id }) {
            versions[index] = version
        }
    }

    private func persistWorkspaceItem(_ item: WorkspaceItem) async throws {
        try await repository.save(item: item)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
    }

    private func syncSelectedDraftItem(using version: DraftVersion) async throws {
        guard var item = selectedDraftItem else { return }
        item.title = version.structuredDoc.title
        item.lastEditedAt = .now
        item.summaryPreview = summaryPreview(for: version.editorDocument, fallback: version.structuredDoc.summary)
        try await repository.save(item: item)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        }
    }

    private func summaryPreview(for document: String, fallback: String) -> String {
        let trimmed = document
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(140))
    }

    private func exportVersionIDs(for item: WorkspaceItem, linkedVersionIDs: Set<UUID>) -> Set<UUID> {
        var versionIDs = linkedVersionIDs
        if item.kind == .export, let currentVersionID = item.currentVersionId {
            versionIDs.insert(currentVersionID)
        }
        return versionIDs
    }

    private func linkedExportItemIDs(for versionIDs: Set<UUID>, excluding itemID: UUID) -> Set<UUID> {
        guard !versionIDs.isEmpty else { return [] }
        return Set(
            items
                .filter {
                    $0.id != itemID &&
                    $0.kind == .export &&
                    $0.currentVersionId.map(versionIDs.contains) == true
                }
                .map(\.id)
        )
    }

    private func failureSummary(for error: Error) -> String {
        "Processing failed. \(userFacingMessage(for: error))"
    }

    private func interruptedSummary(for currentSummary: String) -> String {
        let trimmed = currentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "Processing was interrupted before completion."
        if trimmed.isEmpty || trimmed == "Processing imported content..." {
            return "\(prefix) Delete this draft and run it again if needed."
        }
        if trimmed.hasPrefix(prefix) {
            return trimmed
        }
        return "\(prefix) \(trimmed)"
    }

    private func userFacingMessage(for error: Error) -> String {
        if let processingError = error as? DocumentProcessingError, processingError == .noHealthyProvider {
            return "No healthy AI provider is available. Start Ollama or switch the provider in Settings."
        }

        let description = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.localizedCaseInsensitiveContains("HTTP 504") {
            return "The AI provider timed out before returning a draft. This is usually a provider-side timeout, not a content-format problem. Long inputs, slower models, or temporary provider load can all cause this. Try again, switch to a faster model, or use another provider/API key in Settings."
        }
        if description.localizedCaseInsensitiveContains("timed out") || description.localizedCaseInsensitiveContains("timeout") {
            return "The AI request timed out before it finished. This can happen with long inputs, slower models, or temporary provider instability. Try again, switch to a faster model, or use another provider/API key in Settings."
        }
        if description.localizedCaseInsensitiveContains("HTTP 502") || description.localizedCaseInsensitiveContains("HTTP 503") {
            return "The AI provider is temporarily unavailable. Your content is probably fine. Try again in a moment, or switch to another model/provider in Settings."
        }
        if description.localizedCaseInsensitiveContains("empty error payload") {
            return "The AI provider failed without returning a useful error message. This is usually a provider-side issue, although very long requests can also trigger it. Try again, or switch to another model/provider in Settings."
        }
        return description.isEmpty ? "Something went wrong while updating Notes Curator." : description
    }

    private func startBackgroundRefinement(
        for item: WorkspaceItem,
        baseVersion: DraftVersion,
        sourceText: String
    ) {
        let contentTemplate = resolvedContentTemplate(for: baseVersion)
        let visualTemplate = resolvedVisualTemplate(for: baseVersion)
        let pipelineForRequest = refreshedPipeline()
        let task = Task { @MainActor [self] in
            defer { refinementTasks[item.id] = nil }
            do {
                let refined = try await pipelineForRequest.refineDraftVersion(
                    baseVersion,
                    sourceText: sourceText,
                    contentTemplate: contentTemplate,
                    visualTemplate: visualTemplate
                )
                try Task.checkCancellation()
                try await handleCompletedRefinement(itemID: item.id, refinedVersion: refined)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                do {
                    try await markRefinementFailed(for: item.id, error: error)
                } catch {
                    present(error: error)
                }
            }
        }
        refinementTasks[item.id] = task
    }

    private func handleCompletedRefinement(
        itemID: UUID,
        refinedVersion: DraftVersion
    ) async throws {
        guard !deletedItemIDs.contains(itemID),
              refinementTasks[itemID] != nil,
              items.contains(where: { $0.id == itemID }) else {
            return
        }
        try await repository.save(version: refinedVersion)
        versions.insert(refinedVersion, at: 0)

        guard var item = items.first(where: { $0.id == itemID }) else { return }
        item.refinementStatus = .refined
        item.pendingRefinedVersionId = refinedVersion.id
        item.lastEditedAt = .now
        try await persistRefinementState(for: item)
    }

    private func markRefinementFailed(
        for itemID: UUID,
        error: Error
    ) async throws {
        guard !deletedItemIDs.contains(itemID) else { return }
        guard var item = items.first(where: { $0.id == itemID }) else { return }
        item.refinementStatus = .failed
        item.pendingRefinedVersionId = nil
        item.lastEditedAt = .now
        if item.summaryPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.summaryPreview = "Refinement failed. \(userFacingMessage(for: error))"
        }
        try await persistRefinementState(for: item)
    }

    private func persistRefinementState(for item: WorkspaceItem) async throws {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].refinementStatus = item.refinementStatus
            items[index].pendingRefinedVersionId = item.pendingRefinedVersionId
            items[index].lastEditedAt = item.lastEditedAt
            if !item.summaryPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items[index].summaryPreview = item.summaryPreview
            }

            let snapshot = items[index]
            try await repository.save(item: snapshot)

            if let latest = items.first(where: { $0.id == item.id }), latest != snapshot {
                try await repository.save(item: latest)
            }
        } else {
            try await repository.save(item: item)
            items.insert(item, at: 0)
        }
    }

    private func persistLastSession(_ snapshot: LastSessionSnapshot) async throws {
        try await repository.save(lastSession: snapshot)
        hasSavedSession = true
    }

    private func imageInsertionBlock(for suggestion: ImageSuggestion, language: OutputLanguage) -> String {
        if language == .chinese {
            return """
            图片建议：\(suggestion.title)
            说明：\(suggestion.summary)
            OCR：\(suggestion.ocrText)
            """
        }

        return """
        Image suggestion: \(suggestion.title)
        Summary: \(suggestion.summary)
        OCR: \(suggestion.ocrText)
        """
    }

    private func syncSystemTemplatesIfNeeded() async throws {
        for template in Template.defaultTemplates {
            if let index = templates.firstIndex(where: {
                $0.kind == template.kind &&
                $0.scope == .system &&
                $0.name == template.name
            }) {
                var refreshed = template
                refreshed = Template(
                    id: templates[index].id,
                    kind: template.kind,
                    scope: template.scope,
                    name: template.name,
                    subtitle: template.subtitle,
                    templateDescription: template.templateDescription,
                    format: template.format,
                    body: template.body,
                    config: template.config,
                    storedPackData: template.storedPackData,
                    storedLatexSource: template.storedLatexSource,
                    storedLatexProjectData: template.storedLatexProjectData
                )
                try await repository.save(template: refreshed)
                templates[index] = refreshed
            } else {
                try await repository.save(template: template)
                templates.append(template)
            }
        }

        let supportedSystemTemplateKeys = Set(Template.defaultTemplates.map { "\($0.kind.rawValue):\($0.name.lowercased())" })
        let deprecatedSystemTemplates = templates.filter { template in
            template.scope == .system &&
            supportedSystemTemplateKeys.contains("\(template.kind.rawValue):\(template.name.lowercased())") == false
        }

        for template in deprecatedSystemTemplates {
            try await repository.delete(templateID: template.id)
        }
        let deprecatedIDs = Set(deprecatedSystemTemplates.map(\.id))
        templates.removeAll { deprecatedIDs.contains($0.id) }
        sortTemplates()
    }

    private func removeRedundantTemplateCopiesIfNeeded() async throws {
        let redundantTemplates = templates.filter(isRedundantVisualTemplateCopy)

        guard !redundantTemplates.isEmpty else { return }

        for template in redundantTemplates {
            try await repository.delete(templateID: template.id)
        }
        let redundantIDs = Set(redundantTemplates.map(\.id))
        templates.removeAll { redundantIDs.contains($0.id) }
    }

    private func isRedundantVisualTemplateCopy(_ template: Template) -> Bool {
        template.kind == .visual &&
            template.scope == .user &&
            template.config["source"] != nil &&
            template.config.count == 1
    }

    private func isLegacyBuiltinContentShadow(_ template: Template) -> Bool {
        guard template.kind == .content,
              template.scope == .user,
              template.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              template.storedLatexProjectData == nil,
              template.storedLatexSource?.hasPrefix("% NotesCurator LaTeX Template v1") == true,
              let builtin = Template.builtinContentTemplate(named: template.name, goalType: template.configuredGoalType),
              builtin.scope == .system,
              builtin.format == .latexProject else {
            return false
        }

        return template.subtitle == builtin.subtitle &&
            template.templateDescription == builtin.templateDescription
    }

    private func sortTemplates() {
        templates.sort(by: templateSortOrder(_:_:))
    }

    private func syncEditingPackIntoPendingImport() {
        guard let editingTemplatePack, var review = pendingTemplateImportReview else { return }
        review.templatePack = editingTemplatePack
        pendingTemplateImportReview = review
    }

    private func contentTemplate(id: UUID) -> Template? {
        guard let template = templates.first(where: { $0.kind == .content && $0.id == id }) else {
            return nil
        }
        if isLegacyBuiltinContentShadow(template) {
            return Template.builtinContentTemplate(named: template.name, goalType: template.configuredGoalType) ?? template
        }
        return template
    }

    private func resolvedContentTemplate(named name: String, goalType: GoalType) -> Template? {
        preferredTemplate(named: name, kind: .content)
            ?? Template.builtinContentTemplate(named: name, goalType: goalType)
    }

    private func resolvedContentTemplate(for version: DraftVersion) -> Template? {
        if let templateID = version.structuredDoc.exportMetadata.contentTemplateID,
           let template = contentTemplate(id: templateID) {
            return template
        }
        return resolvedContentTemplate(
            named: version.structuredDoc.exportMetadata.contentTemplateName,
            goalType: version.goalType
        )
    }

    private func visualTemplate(named name: String) -> Template? {
        preferredTemplate(named: name, kind: .visual)
    }

    private func resolvedVisualTemplate(for version: DraftVersion) -> Template? {
        if let visualID = version.structuredDoc.exportMetadata.visualTemplateID,
           let template = templates.first(where: { $0.kind == .visual && $0.id == visualID }) {
            return template
        }
        return visualTemplate(named: version.structuredDoc.exportMetadata.visualTemplateName)
    }

    private func effectiveTemplates(of kind: TemplateKind) -> [Template] {
        let ordered = templates
            .filter { template in
                template.kind == kind &&
                    (kind != .content || isLegacyBuiltinContentShadow(template) == false)
            }
            .sorted(by: templateSortOrder(_:_:))

        var preferredByName: [String: Template] = [:]
        for template in ordered {
            let key = templateLibraryKey(for: template.name)
            if let existing = preferredByName[key], existing.scope == .user {
                continue
            }
            preferredByName[key] = template
        }

        return preferredByName.values.sorted(by: templateSortOrder(_:_:))
    }

    private func preferredTemplate(named name: String, kind: TemplateKind) -> Template? {
        let matches = templates.filter {
            $0.kind == kind &&
                templateLibraryKey(for: $0.name) == templateLibraryKey(for: name) &&
                (kind != .content || isLegacyBuiltinContentShadow($0) == false)
        }
        return matches.first(where: { $0.scope == .user })
            ?? matches.first(where: { $0.scope == .system })
    }

    private func templateLibraryKey(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func templateSortOrder(_ lhs: Template, _ rhs: Template) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }

        let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }

        if lhs.scope != rhs.scope { return lhs.scope.rawValue < rhs.scope.rawValue }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
