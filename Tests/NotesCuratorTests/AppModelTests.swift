import Foundation
import Testing
@testable import NotesCurator

@MainActor
struct AppModelTests {
    @Test
    func primarySystemContentTemplatesUsePackBackedDefaults() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
            primaryProvider: StubProvider(isHealthy: true, response: .empty)
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()

        let summary = try #require(model.contentTemplates.first(where: { $0.name == "Summary" }))
        let structured = try #require(model.contentTemplates.first(where: { $0.name == "Structured Notes" }))
        let lecture = try #require(model.contentTemplates.first(where: { $0.name == "Lecture Notes" }))
        let studyGuide = try #require(model.contentTemplates.first(where: { $0.name == "Study Guide" }))
        let deepDive = try #require(model.contentTemplates.first(where: { $0.name == "Technical Deep Dive" }))
        let formal = try #require(model.contentTemplates.first(where: { $0.name == "Formal Document" }))

        #expect(summary.storedPackData != nil)
        #expect(structured.storedPackData != nil)
        #expect(lecture.storedPackData != nil)
        #expect(studyGuide.storedPackData != nil)
        #expect(deepDive.storedPackData != nil)
        #expect(formal.storedPackData != nil)
        #expect(summary.storedLatexSource?.contains("\\documentclass") == true)
        #expect(formal.storedLatexSource?.contains("% notescurator.block:") == true)
        #expect(summary.body.isEmpty)
        #expect(structured.body.isEmpty)
        #expect(lecture.body.isEmpty)
        #expect(studyGuide.body.isEmpty)
        #expect(deepDive.body.isEmpty)
        #expect(formal.body.isEmpty)
        #expect(model.contentTemplates.contains(where: { $0.name == "Action Items" }) == false)
    }

    @Test
    func userContentTemplateOverrideShadowsSystemPresetAcrossReloads() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
            primaryProvider: StubProvider(isHealthy: true, response: .empty)
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()

        let systemTemplate = try #require(model.contentTemplates.first(where: { $0.name == "Structured Notes" }))
        let override = Template(
            kind: .content,
            scope: .user,
            name: systemTemplate.name,
            subtitle: "Customized balanced structure",
            templateDescription: "Keeps the same preset name but uses a custom markdown body.",
            format: .markdownTemplate,
            body: Template.starterContentTemplate().body.replacingOccurrences(of: "## Notes", with: "## Custom Notes"),
            config: systemTemplate.config
        )

        try await model.saveTemplate(override)

        let visibleTemplate = try #require(model.contentTemplates.first(where: { $0.name == systemTemplate.name }))
        #expect(visibleTemplate.id == override.id)
        #expect(model.templates.contains(where: { $0.id == systemTemplate.id }))
        #expect(model.templates.contains(where: { $0.id == override.id }))

        let reloadedModel = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await reloadedModel.load()

        let reloadedVisibleTemplate = try #require(reloadedModel.contentTemplates.first(where: { $0.name == systemTemplate.name }))
        #expect(reloadedVisibleTemplate.id == override.id)
        #expect(reloadedModel.templates.contains(where: { $0.scope == .system && $0.name == systemTemplate.name }))
        #expect(reloadedModel.templates.contains(where: { $0.scope == .user && $0.name == systemTemplate.name }))
    }

    @Test
    func appModelPrefersPackBackedOverrideOverLegacySystemTemplate() async throws {
        let model = try await loadedModelWithReadyDraft()
        let imported = Template.packBacked(
            TemplatePackDefaults.pack(for: .technicalNote, named: "Structured Notes"),
            scope: .user
        )

        try await model.saveTemplate(imported)

        #expect(
            try model.contentTemplates
                .first(where: { $0.name == "Structured Notes" })?
                .templatePack()
                .identity
                .name == "Structured Notes"
        )
    }

    @Test
    func appModelStoresImportReviewStateBeforeSavingTemplate() async throws {
        let model = NotesCuratorAppModel(
            repository: MemoryRepository(),
            pipeline: DocumentProcessingPipeline(
                parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
                primaryProvider: StubProvider(isHealthy: true, response: .empty)
            )
        )
        try await model.load()

        try model.beginLatexTemplateImport(SampleLatexSources.technicalNote)

        #expect(model.pendingTemplateImportReview != nil)
        #expect(model.pendingTemplateImportReview?.templatePack.identity.name.isEmpty == false)
    }

    @Test
    func appModelCanSavePendingImportedTemplate() async throws {
        let model = NotesCuratorAppModel(
            repository: MemoryRepository(),
            pipeline: DocumentProcessingPipeline(
                parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
                primaryProvider: StubProvider(isHealthy: true, response: .empty)
            )
        )
        try await model.load()
        try model.beginLatexTemplateImport(SampleLatexSources.technicalNote)

        let saved = try await model.savePendingTemplateImport()

        #expect(saved?.scope == .user)
        #expect(saved?.storedLatexSource == SampleLatexSources.technicalNote)
        #expect(model.pendingTemplateImportReview == nil)
        #expect(model.contentTemplates.contains(where: { $0.name == saved?.name }))
    }

    @Test
    func builderLiteCanReorderBlocksRenameTitlesAndChangeEmptyBehavior() async throws {
        let model = try await loadedModelWithImportedPack()
        let initial = try #require(model.editingTemplatePack)
        let renamedBlockID = initial.layout.blocks[0].id
        let movedBlockID = initial.layout.blocks[3].id

        model.moveEditingTemplateBlock(from: 3, to: 1)
        model.renameEditingTemplateBlock(renamedBlockID, to: "Quick Summary")
        model.setEditingTemplateEmptyBehavior(
            renamedBlockID,
            authoring: .placeholder,
            preview: .hide,
            export: .hide
        )

        let updated = try #require(model.editingTemplatePack)
        #expect(updated.layout.blocks[1].id == movedBlockID)
        #expect(updated.layout.blocks.first(where: { $0.id == renamedBlockID })?.titleOverride == "Quick Summary")
        #expect(updated.layout.blocks.first(where: { $0.id == renamedBlockID })?.emptyBehavior.preview == .hide)
        #expect(updated.layout.blocks.first(where: { $0.id == renamedBlockID })?.emptyBehavior.export == .hide)
    }

    @Test
    func processingUsesImportedPackWhenTemplateIsSelected() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "Discussed launch sequencing, owners, and the follow-up plan.",
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Discussed launch sequencing...")],
                    images: []
                )
            ),
            primaryProvider: StubProvider(
                isHealthy: true,
                response: ProviderDraftResponse(
                    title: "Imported Pack Draft",
                    summary: "Imported pack summary.",
                    keyPoints: ["Pack-specific structure"],
                    sections: [StructuredSection(title: "Overview", body: "Imported pack body.")],
                    actionItems: ["Assign the owner"],
                    renderedDocument: "provider markdown should be ignored"
                )
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()

        var pack = TemplatePackDefaults.pack(for: .technicalNote, named: "Imported Technical Template")
        pack.layout.blocks = [
            TemplateBlockSpec(blockType: .summary, fieldBinding: "overview"),
            TemplateBlockSpec(blockType: .actionItems, fieldBinding: "action_items", titleOverride: "Follow Through")
        ]
        let imported = Template.packBacked(pack, scope: .user)
        try await model.saveTemplate(imported)

        let workspace = try await model.createWorkspace(named: "Imported Processing")
        try await model.processNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "Discussed launch sequencing, owners, and the follow-up plan.",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: imported.name,
                visualTemplateName: "Oceanic Blue"
            )
        )

        #expect(model.currentVersion?.structuredDoc.exportMetadata.contentTemplateName == imported.name)
        #expect(model.currentVersion?.structuredDoc.exportMetadata.contentTemplatePackData != nil)
        #expect(model.currentVersion?.editorDocument.contains("## Follow Through") == true)
    }

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
    func selectingDifferentContentTemplateDoesNotAutoRegenerateCurrentDraft() async throws {
        let model = try await loadedModelWithReadyDraft()
        let originalDocument = try #require(model.currentVersion?.editorDocument)
        let studyGuide = try #require(model.contentTemplates.first(where: { $0.name == "Study Guide" }))

        try await model.updateSelectedContentTemplate(studyGuide.id)

        #expect(model.currentVersion?.editorDocument == originalDocument)
        #expect(model.currentVersion?.structuredDoc.exportMetadata.contentTemplateID == studyGuide.id)
        #expect(model.currentVersion?.structuredDoc.exportMetadata.renderedContentTemplateID != studyGuide.id)
    }

    @Test
    func regenerateCurrentDraftUsesPersistedGenerationSourceText() async throws {
        let model = try await loadedModelWithReadyDraft()
        let formalDocument = try #require(model.contentTemplates.first(where: { $0.name == "Formal Document" }))

        try await model.updateSelectedContentTemplate(formalDocument.id)
        try await model.regenerateCurrentDraftWithSelectedTemplate()

        #expect(model.currentVersion?.editorDocument.isEmpty == false)
        #expect(model.currentVersion?.structuredDoc.exportMetadata.renderedContentTemplateID == formalDocument.id)
        #expect(model.currentVersion?.generationSourceText != nil)
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
    func appModelSyncsEditedMarkdownIntoStructuredPreviewAndWorkspaceTitle() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "delegatecall allows a contract to run another contract's code in its own context.",
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "delegatecall allows...")],
                    images: []
                )
            ),
            primaryProvider: StubProvider(
                isHealthy: true,
                response: ProviderDraftResponse(
                    title: "Original Title",
                    summary: "Original summary",
                    keyPoints: ["Original point"],
                    sections: [StructuredSection(title: "Overview", body: "Original body")],
                    actionItems: [],
                    renderedDocument: "Original Title\n\nSummary\nOriginal summary"
                )
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Editing")

        try await model.processNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "delegatecall allows a contract to run another contract's code in its own context.",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .chinese,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Ivory Lecture"
            )
        )

        let editedDocument = """
        # Delegatecall 机制详解

        ## 摘要
        Delegatecall 允许一个合约在调用者上下文中执行外部代码。

        ## 复习提示
        - 它和 call 的最大区别是什么？
        - 为什么会影响存储布局？

        ## 核心要点
        - msg.sender 和 msg.value 会沿用调用者上下文。
        - 必须确保存储槽布局兼容。

        ## 1. 核心概念
        Delegatecall 不会切换执行上下文。
        - 状态修改发生在调用者合约中。
        """

        try await model.updateEditorDocument(editedDocument)

        let version = try #require(model.currentVersion)
        #expect(version.structuredDoc.title == "Delegatecall 机制详解")
        #expect(version.structuredDoc.summary == "Delegatecall 允许一个合约在调用者上下文中执行外部代码。")
        #expect(version.structuredDoc.cueQuestions == ["它和 call 的最大区别是什么？", "为什么会影响存储布局？"])
        #expect(version.structuredDoc.keyPoints == ["msg.sender 和 msg.value 会沿用调用者上下文。", "必须确保存储槽布局兼容。"])
        #expect(version.structuredDoc.sections.count == 1)
        #expect(version.structuredDoc.sections.first?.title == "1. 核心概念")
        #expect(version.structuredDoc.sections.first?.body == "Delegatecall 不会切换执行上下文。")
        #expect(version.structuredDoc.sections.first?.bulletPoints == ["状态修改发生在调用者合约中。"])
        #expect(model.selectedDraftItem?.title == "Delegatecall 机制详解")
    }

    @Test
    func appModelUsesEditedTitleWhenSavingAndExporting() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "delegatecall allows a contract to reuse code.",
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "delegatecall allows...")],
                    images: []
                )
            ),
            primaryProvider: StubProvider(
                isHealthy: true,
                response: ProviderDraftResponse(
                    title: "Original Draft",
                    summary: "Original summary",
                    keyPoints: ["Original point"],
                    sections: [StructuredSection(title: "Overview", body: "Original body")],
                    actionItems: [],
                    renderedDocument: "Original Draft\n\nSummary\nOriginal summary"
                )
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Exports")

        try await model.processNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "delegatecall allows a contract to reuse code.",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            )
        )

        try await model.updateEditorDocument(
            """
            # Updated Delegatecall Title

            ## Summary
            Updated summary for export naming.

            ## Key Points
            - Keep the exported filename in sync.
            """
        )
        try await model.saveManualVersion()

        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exported = try await model.exportCurrentDraft(format: .markdown, to: outputDirectory)

        #expect(model.currentVersion?.structuredDoc.title == "Updated Delegatecall Title")
        #expect(model.selectedDraftItem?.title == "Updated Delegatecall Title")
        #expect(exported?.lastPathComponent == "updated-delegatecall-title.md")
    }

    @Test
    func appModelRemovesStaleStructuredSectionsWhenEditorDeletesThem() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "Initial structured note",
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Initial structured note")],
                    images: []
                )
            ),
            primaryProvider: StubProvider(
                isHealthy: true,
                response: ProviderDraftResponse(
                    title: "Structured Draft",
                    summary: "Original summary",
                    keyPoints: ["Point A"],
                    sections: [
                        StructuredSection(title: "Overview", body: "Old section body"),
                        StructuredSection(title: "Details", body: "Another section")
                    ],
                    actionItems: ["Follow up"],
                    renderedDocument: """
                    Structured Draft

                    Summary
                    Original summary

                    Overview
                    Old section body
                    """
                )
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Cleanup")

        try await model.processNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "Initial structured note",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            )
        )

        try await model.updateEditorDocument(
            """
            # Structured Draft

            ## Summary
            Only the summary should remain after cleanup.
            """
        )

        let version = try #require(model.currentVersion)
        #expect(version.structuredDoc.summary == "Only the summary should remain after cleanup.")
        #expect(version.structuredDoc.sections.isEmpty)
        #expect(version.structuredDoc.keyPoints.isEmpty)
        #expect(version.structuredDoc.actionItems.isEmpty)
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
        #expect(model.preferences.modelName == "qwen3.5:9b")
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
    func appPreferencesDefaultRecommendedModelUsesQwenThreePointFiveNineB() {
        #expect(AppPreferences.default.modelName == "qwen3.5:9b")
        #expect(AppPreferences.recommendedLocalOllama.modelName == "qwen3.5:9b")
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
    func appModelDeletesReadyDraftsAndCascadesDerivedExports() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "This note should be deletable after it is generated.",
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "This note should be deletable...")],
                    images: []
                )
            ),
            primaryProvider: StubProvider(
                isHealthy: true,
                response: ProviderDraftResponse(
                    title: "Deletable Note",
                    summary: "A completed note that also has an export.",
                    keyPoints: ["Delete should work after completion"],
                    sections: [StructuredSection(title: "Overview", body: "Ready notes must remain removable.")],
                    actionItems: ["Verify delete behavior"],
                    renderedDocument: "Ready notes must remain removable."
                )
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Deletion Coverage")

        try await model.processNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "This note should be deletable after it is generated.",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            )
        )

        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exportURL = try await model.exportCurrentDraft(format: .txt, to: exportDirectory)
        #expect(exportURL != nil)
        #expect(model.workspaceItems(in: workspace.id, kind: .export).count == 1)
        #expect(model.exports.count == 1)

        let readyDraft = try #require(model.workspaceItems(in: workspace.id, kind: .draft).first)
        #expect(readyDraft.status == .ready)

        try await model.deleteWorkspaceItem(readyDraft.id)

        #expect(model.workspaceItems(in: workspace.id, kind: .draft).isEmpty)
        #expect(model.workspaceItems(in: workspace.id, kind: .export).isEmpty)
        #expect(model.exports.isEmpty)
        #expect(model.versions.isEmpty)
        #expect(model.selectedItemID == nil)
        #expect(model.currentFlow == nil)
        #expect(repository.snapshot.items.isEmpty)
        #expect(repository.snapshot.versions.isEmpty)
        #expect(repository.snapshot.exports.isEmpty)
    }

    @Test
    func appModelCanDeleteAnExportRecordWithoutTouchingItsDraft() async throws {
        let repository = MemoryRepository()
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "Keep the note, remove only the export record.",
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Keep the note...")],
                    images: []
                )
            ),
            primaryProvider: StubProvider(
                isHealthy: true,
                response: ProviderDraftResponse(
                    title: "Export Record Test",
                    summary: "A note with one export record.",
                    keyPoints: ["Exports should be independently removable"],
                    sections: [StructuredSection(title: "Overview", body: "Delete only the export record from the exports page.")],
                    actionItems: [],
                    renderedDocument: "Delete only the export record."
                )
            )
        )

        let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
        try await model.load()
        let workspace = try await model.createWorkspace(named: "Exports")

        try await model.processNewNote(
            in: workspace.id,
            intake: IntakeRequest(
                pastedText: "Keep the note, remove only the export record.",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            )
        )

        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exportURL = try await model.exportCurrentDraft(format: .pdf, to: exportDirectory)
        #expect(exportURL != nil)

        let exportRecord = try #require(model.exports.first)
        let draftCountBeforeDelete = model.workspaceItems(in: workspace.id, kind: .draft).count
        let exportItemCountBeforeDelete = model.workspaceItems(in: workspace.id, kind: .export).count
        let noteStillExists = model.selectedDraftItem?.id

        try await model.deleteExportRecord(exportRecord.id)

        #expect(model.exports.isEmpty)
        #expect(repository.snapshot.exports.isEmpty)
        #expect(model.workspaceItems(in: workspace.id, kind: .draft).count == draftCountBeforeDelete)
        #expect(model.workspaceItems(in: workspace.id, kind: .export).count == exportItemCountBeforeDelete)
        #expect(model.selectedDraftItem?.id == noteStillExists)
        #expect(!model.versions.isEmpty)
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
        #expect(model.templates.contains { $0.name == "Rose Studio" && $0.scope == .system })
        #expect(model.templates.contains { $0.name == "Emerald Grove" } == false)
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
    func delete(exportID: UUID) async throws { snapshot.exports.removeAll { $0.id == exportID } }
    func delete(itemID: UUID) async throws {
        let item = snapshot.items.first { $0.id == itemID }
        let linkedVersionIDs = Set(snapshot.versions.filter { $0.workspaceItemId == itemID }.map(\.id))
        var exportVersionIDs = linkedVersionIDs
        if item?.kind == .export, let currentVersionID = item?.currentVersionId {
            exportVersionIDs.insert(currentVersionID)
        }
        let linkedExportItemIDs = Set(
            snapshot.items
                .filter {
                    $0.id != itemID &&
                    $0.kind == .export &&
                    $0.currentVersionId.map(exportVersionIDs.contains) == true
                }
                .map(\.id)
        )

        snapshot.items.removeAll { $0.id == itemID || linkedExportItemIDs.contains($0.id) }
        snapshot.versions.removeAll { linkedVersionIDs.contains($0.id) }
        snapshot.exports.removeAll { exportVersionIDs.contains($0.draftVersionId) }
    }
    func save(preferences: AppPreferences) async throws { snapshot.preferences = preferences }
    func save(lastSession: LastSessionSnapshot) async throws { snapshot.lastSession = lastSession }
    func loadSnapshot() async throws -> RepositorySnapshot { snapshot }

    private func upsert<T: Identifiable & Equatable>(_ value: T, into values: [T]) -> [T] {
        let filtered = values.filter { $0.id != value.id }
        return filtered + [value]
    }
}

@MainActor
private func loadedModelWithReadyDraft() async throws -> NotesCuratorAppModel {
    let repository = MemoryRepository()
    let pipeline = DocumentProcessingPipeline(
        parser: StubParser(
            parsed: ParsedDocument(
                text: "Discussed launch sequencing, owners, and the follow-up plan.",
                sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Discussed launch sequencing...")],
                images: []
            )
        ),
        primaryProvider: StubProvider(
            isHealthy: true,
            response: ProviderDraftResponse(
                title: "Launch Planning Note",
                summary: "The team aligned on sequencing, ownership, and follow-up.",
                cueQuestions: ["What should happen first?"],
                keyPoints: ["Ownership is now clearer."],
                sections: [StructuredSection(title: "Context", body: "The team needs a cleaner rollout sequence.")],
                actionItems: ["Assign owners", "Track deadlines"],
                renderedDocument: "provider text that should not be the source of truth"
            )
        )
    )

    let model = NotesCuratorAppModel(repository: repository, pipeline: pipeline)
    try await model.load()
    let workspace = try await model.createWorkspace(named: "Template Switching")
    try await model.processNewNote(
        in: workspace.id,
        intake: IntakeRequest(
            pastedText: "Discussed launch sequencing, owners, and the follow-up plan.",
            fileURLs: [],
            goalType: .structuredNotes,
            outputLanguage: .english,
            contentTemplateName: "Structured Notes",
            visualTemplateName: "Oceanic Blue"
        )
    )
    return model
}

@MainActor
private func loadedModelWithImportedPack() async throws -> NotesCuratorAppModel {
    let model = NotesCuratorAppModel(
        repository: MemoryRepository(),
        pipeline: DocumentProcessingPipeline(
            parser: StubParser(parsed: ParsedDocument(text: "", sources: [], images: [])),
            primaryProvider: StubProvider(isHealthy: true, response: .empty)
        )
    )
    try await model.load()
    try model.beginLatexTemplateImport(SampleLatexSources.technicalNote)
    return model
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
