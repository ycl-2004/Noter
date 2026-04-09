import AppKit
import Foundation
import PDFKit
import Testing
@testable import NotesCurator

struct ProcessingAndExportTests {
    @Test
    func processingPipelineFallsBackAndBuildsLocalizedDraft() async throws {
        let primary = StubProvider(
            isHealthy: false,
            response: .empty
        )

        let fallback = StubProvider(
            isHealthy: true,
            response: ProviderDraftResponse(
                title: "产品会议纪要",
                summary: "总结了预算、物流和品牌方向。",
                keyPoints: ["物流成本偏高", "预算需要下调", "品牌视觉待更新"],
                sections: [
                    StructuredSection(title: "重点", body: "需要围绕预算、物流和品牌做后续。")
                ],
                actionItems: ["周二前整理正式文档"],
                renderedDocument: "摘要\n- 物流成本偏高\n- 预算需要下调\n- 品牌视觉待更新"
            )
        )

        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "We discussed logistics costs, budget cuts, and new brand guidelines.",
                    sources: [
                        SourceReference(kind: .pastedText, title: "Input", excerpt: "We discussed logistics...")
                    ],
                    images: [
                        ParsedImageAsset(
                            title: "Budget Slide",
                            summary: "A presentation slide mentioning 15% reduction",
                            ocrText: "15% reduction across marketing"
                        )
                    ]
                )
            ),
            primaryProvider: primary,
            fallbackProvider: fallback
        )

        let itemID = UUID()
        let draft = try await pipeline.process(
            intake: IntakeRequest(
                pastedText: "We discussed logistics costs, budget cuts, and new brand guidelines.",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .chinese,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            ),
            workspaceItemId: itemID
        )

        #expect(draft.workspaceItemId == itemID)
        #expect(draft.outputLanguage == .chinese)
        #expect(draft.structuredDoc.title == "产品会议纪要")
        #expect(draft.editorDocument.contains("# 产品会议纪要"))
        #expect(draft.imageSuggestions.count == 1)
        #expect(draft.imageSuggestions.first?.title == "Budget Slide")
    }

    @Test
    func processingUsesLocalTemplateRendererInsteadOfProviderRenderedDocument() async throws {
        let provider = StubProvider(
            isHealthy: true,
            response: ProviderDraftResponse(
                title: "Action Plan",
                summary: "Task-first summary",
                keyPoints: ["Keep the next steps visible."],
                sections: [StructuredSection(title: "Context", body: "The team needs a cleaner rollout sequence.")],
                actionItems: ["Assign owners", "Track deadlines"],
                renderedDocument: "provider freeform markdown that should be ignored"
            )
        )

        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "source",
                    sources: [],
                    images: []
                )
            ),
            primaryProvider: provider
        )

        let result = try await pipeline.process(
            intake: IntakeRequest(
                pastedText: "source",
                fileURLs: [],
                goalType: .actionItems,
                outputLanguage: .english,
                contentTemplateName: "Action Items",
                visualTemplateName: "Oceanic Blue"
            ),
            workspaceItemId: UUID()
        )

        #expect(result.editorDocument != "provider freeform markdown that should be ignored")
        #expect(result.editorDocument.contains("Next Steps"))
    }

    @Test
    func processingUsesPackBackedTemplateForEditorOutput() async throws {
        let provider = StubProvider(
            isHealthy: true,
            response: ProviderDraftResponse(
                title: "Imported Template Draft",
                summary: "Imported pack summary",
                keyPoints: ["Keep the imported pack layout"],
                sections: [StructuredSection(title: "Overview", body: "Imported pack body")],
                actionItems: ["Assign the owner"],
                renderedDocument: "provider markdown should be ignored"
            )
        )

        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "source",
                    sources: [],
                    images: []
                )
            ),
            primaryProvider: provider
        )

        var pack = TemplatePackDefaults.pack(for: .technicalNote, named: "Imported Technical Template")
        pack.layout.blocks = [
            TemplateBlockSpec(blockType: .summary, fieldBinding: "overview"),
            TemplateBlockSpec(blockType: .actionItems, fieldBinding: "action_items", titleOverride: "Follow Through")
        ]
        let importedTemplate = Template.packBacked(pack, scope: .user)

        let result = try await pipeline.process(
            intake: IntakeRequest(
                pastedText: "source",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Imported Technical Template",
                visualTemplateName: "Oceanic Blue"
            ),
            workspaceItemId: UUID(),
            contentTemplate: importedTemplate
        )

        #expect(result.editorDocument.contains("## Follow Through"))
        #expect(result.structuredDoc.exportMetadata.contentTemplatePackData != nil)
    }

    @Test
    func processingPipelineUsesSinglePassForShortInputs() async throws {
        let recorder = DraftRequestRecorder()
        let provider = RecordingProvider(recorder: recorder)
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: "Merkle trees help verify whether data exists in a set without scanning every item.",
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Merkle trees help verify...")],
                    images: []
                )
            ),
            primaryProvider: provider
        )

        _ = try await pipeline.process(
            intake: IntakeRequest(
                pastedText: "Merkle trees help verify whether data exists in a set without scanning every item.",
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            ),
            workspaceItemId: UUID()
        )

        let requests = await recorder.snapshot()
        #expect(requests.count == 1)
        #expect(requests.first?.generationMode == .finalDocument)
    }

    @Test
    func processingPipelineChunksLongInputsAndMergesDigests() async throws {
        let recorder = DraftRequestRecorder()
        let provider = RecordingProvider(recorder: recorder)
        let paragraph = Array(repeating: "Merkle trees store hashes in leaves and combine them upward so membership proofs stay logarithmic in size.", count: 8).joined(separator: " ")
        let longText = Array(repeating: paragraph, count: 16).joined(separator: "\n\n")

        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: longText,
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Long input")],
                    images: []
                )
            ),
            primaryProvider: provider
        )

        let draft = try await pipeline.process(
            intake: IntakeRequest(
                pastedText: longText,
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            ),
            workspaceItemId: UUID()
        )

        let requests = await recorder.snapshot()
        let chunkRequests = requests.filter { $0.generationMode == .chunkDigest }
        let mergedRequest = try #require(requests.first { $0.generationMode == .mergedDocument })

        #expect(chunkRequests.count > 1)
        #expect(mergedRequest.rawText.contains("Chunk 1"))
        #expect(mergedRequest.rawText.count < longText.count)
        #expect(draft.structuredDoc.title == "Merged Draft")
    }

    @Test
    func processingPipelineRunsChunkDigestsConcurrently() async throws {
        let recorder = DraftRequestRecorder()
        let concurrencyRecorder = ConcurrentGenerateRecorder()
        let provider = DelayedRecordingProvider(
            recorder: recorder,
            concurrencyRecorder: concurrencyRecorder,
            delayNanoseconds: 150_000_000
        )
        let paragraph = Array(repeating: "Merkle trees store hashes in leaves and combine them upward so membership proofs stay logarithmic in size.", count: 8).joined(separator: " ")
        let longText = Array(repeating: paragraph, count: 16).joined(separator: "\n\n")

        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: longText,
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Long input")],
                    images: []
                )
            ),
            primaryProvider: provider
        )

        _ = try await pipeline.process(
            intake: IntakeRequest(
                pastedText: longText,
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            ),
            workspaceItemId: UUID()
        )

        let requests = await recorder.snapshot()
        let chunkRequests = requests.filter { $0.generationMode == .chunkDigest }
        let maxActiveCount = await concurrencyRecorder.snapshot()

        #expect(chunkRequests.count > 1)
        #expect(maxActiveCount > 1)
    }

    @Test
    func processingPipelineCanRouteChunkingAndRepairToDifferentProviders() async throws {
        let finalRecorder = DraftRequestRecorder()
        let chunkRecorder = DraftRequestRecorder()
        let repairRecorder = ValidationRecorder()

        let finalProvider = WorkflowRecordingProvider(
            generateRecorder: finalRecorder,
            validationRecorder: nil,
            titlePrefix: "final"
        )
        let chunkProvider = WorkflowRecordingProvider(
            generateRecorder: chunkRecorder,
            validationRecorder: nil,
            titlePrefix: "chunk"
        )
        let repairProvider = WorkflowRecordingProvider(
            generateRecorder: nil,
            validationRecorder: repairRecorder,
            titlePrefix: "repair"
        )

        let paragraph = Array(repeating: "Distributed systems notes benefit from chunked summarization before the final structured handout is written.", count: 8).joined(separator: " ")
        let longText = Array(repeating: paragraph, count: 16).joined(separator: "\n\n")

        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: longText,
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Long input")],
                    images: []
                )
            ),
            primaryProvider: finalProvider,
            chunkProvider: chunkProvider,
            repairProvider: repairProvider
        )

        let draft = try await pipeline.process(
            intake: IntakeRequest(
                pastedText: longText,
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .english,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            ),
            workspaceItemId: UUID()
        )

        let finalRequests = await finalRecorder.snapshot()
        let chunkRequests = await chunkRecorder.snapshot()
        let repairDrafts = await repairRecorder.snapshot()

        #expect(finalRequests.contains(where: { $0.generationMode == .mergedDocument }))
        #expect(!finalRequests.contains(where: { $0.generationMode == .chunkDigest }))
        #expect(chunkRequests.allSatisfy { $0.generationMode == .chunkDigest })
        #expect(chunkRequests.count > 1)
        #expect(repairDrafts.count == 1)
        #expect(draft.structuredDoc.title == "repair-validated")
        #expect(draft.structuredDoc.keyPoints.contains("validated:repair"))
    }

    @Test
    func processingPipelineCanRouteFormalDocumentPolishToDedicatedProvider() async throws {
        let finalRecorder = DraftRequestRecorder()
        let polishRecorder = ValidationRecorder()
        let repairRecorder = ValidationRecorder()

        let finalProvider = WorkflowRecordingProvider(
            generateRecorder: finalRecorder,
            validationRecorder: nil,
            titlePrefix: "final"
        )
        let polishProvider = WorkflowRecordingProvider(
            generateRecorder: nil,
            validationRecorder: polishRecorder,
            titlePrefix: "polish"
        )
        let repairProvider = WorkflowRecordingProvider(
            generateRecorder: nil,
            validationRecorder: repairRecorder,
            titlePrefix: "repair"
        )

        let text = "This strategy memo explains pricing changes, operational constraints, and customer communication updates."
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: text,
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Strategy memo")],
                    images: []
                )
            ),
            primaryProvider: finalProvider,
            polishProvider: polishProvider,
            repairProvider: repairProvider
        )

        let draft = try await pipeline.process(
            intake: IntakeRequest(
                pastedText: text,
                fileURLs: [],
                goalType: .formalDocument,
                outputLanguage: .english,
                contentTemplateName: "Formal Document",
                visualTemplateName: "Oceanic Blue"
            ),
            workspaceItemId: UUID()
        )

        let finalRequests = await finalRecorder.snapshot()
        let polishDrafts = await polishRecorder.snapshot()
        let repairDrafts = await repairRecorder.snapshot()

        #expect(finalRequests.count == 1)
        #expect(polishDrafts.count == 1)
        #expect(repairDrafts.count == 1)
        #expect(draft.structuredDoc.keyPoints.contains("validated:repair"))
    }

    @Test
    func processingPipelineCanRouteTranslationPolishWhenLanguageChanges() async throws {
        let polishRecorder = ValidationRecorder()
        let repairRecorder = ValidationRecorder()

        let finalProvider = WorkflowRecordingProvider(
            generateRecorder: nil,
            validationRecorder: nil,
            titlePrefix: "final"
        )
        let polishProvider = WorkflowRecordingProvider(
            generateRecorder: nil,
            validationRecorder: polishRecorder,
            titlePrefix: "polish"
        )
        let repairProvider = WorkflowRecordingProvider(
            generateRecorder: nil,
            validationRecorder: repairRecorder,
            titlePrefix: "repair"
        )

        let text = "The workshop covered OCR quality, export formatting, and note organization for multilingual teams."
        let pipeline = DocumentProcessingPipeline(
            parser: StubParser(
                parsed: ParsedDocument(
                    text: text,
                    sources: [SourceReference(kind: .pastedText, title: "Input", excerpt: "Workshop")],
                    images: []
                )
            ),
            primaryProvider: finalProvider,
            polishProvider: polishProvider,
            repairProvider: repairProvider
        )

        _ = try await pipeline.process(
            intake: IntakeRequest(
                pastedText: text,
                fileURLs: [],
                goalType: .structuredNotes,
                outputLanguage: .chinese,
                contentTemplateName: "Structured Notes",
                visualTemplateName: "Oceanic Blue"
            ),
            workspaceItemId: UUID()
        )

        let polishDrafts = await polishRecorder.snapshot()
        let repairDrafts = await repairRecorder.snapshot()

        #expect(polishDrafts.count == 1)
        #expect(repairDrafts.count == 1)
    }

    @Test
    @MainActor
    func exportersCreateMarkdownDocxAndPDFArtifacts() throws {
        let draft = DraftVersion(
            workspaceItemId: UUID(),
            goalType: .formalDocument,
            outputLanguage: .english,
            editorDocument: """
            # Project Strategy

            > Revenue grew while operations stayed efficient.

            ## Cue Questions
            - What explains the revenue growth?

            ## Executive Summary
            Revenue grew 24% year over year.

            ## Key Points
            - Revenue up 24%
            - Operations efficient

            ### Main takeaway
            Growth came without operational sprawl.

            ## Glossary
            - **YoY**: Year over year.

            ## Study Cards
            - Q: What explains the revenue growth?
            - A: The note ties growth to stronger execution while keeping operations efficient.

            ## Review Questions
            - Which efficiency metrics support the strategy?

            ## Action Items
            - Share strategy update
            """,
            structuredDoc: StructuredDocument(
                title: "Project Strategy",
                summary: "Revenue grew while operations stayed efficient.",
                cueQuestions: ["What explains the revenue growth?"],
                keyPoints: ["Revenue up 24%", "Operations efficient"],
                sections: [
                    StructuredSection(
                        title: "Executive Summary",
                        body: "Revenue grew 24% year over year.",
                        bulletPoints: ["Margin stayed healthy", "Team execution improved"]
                    )
                ],
                glossary: [GlossaryItem(term: "YoY", definition: "Year over year.")],
                callouts: [
                    StructuredCallout(kind: .keyIdea, title: "Main takeaway", body: "Growth came without operational sprawl.")
                ],
                studyCards: [
                    StudyCard(
                        question: "What explains the revenue growth?",
                        answer: "The note ties growth to stronger execution while keeping operations efficient."
                    )
                ],
                actionItems: ["Share strategy update"],
                reviewQuestions: ["Which efficiency metrics support the strategy?"],
                imageSlots: [],
                exportMetadata: ExportMetadata(
                    contentTemplateName: "Formal Document",
                    visualTemplateName: "Oceanic Blue",
                    preferredFormat: .pdf
                )
            ),
            sourceRefs: [],
            imageSuggestions: []
        )

        let exporter = ExportCoordinator()
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let markdownURL = try exporter.export(draft: draft, format: .markdown, to: outputDirectory)
        let textURL = try exporter.export(draft: draft, format: .txt, to: outputDirectory)
        let htmlURL = try exporter.export(draft: draft, format: .html, to: outputDirectory)
        let rtfURL = try exporter.export(draft: draft, format: .rtf, to: outputDirectory)
        let docxURL = try exporter.export(draft: draft, format: .docx, to: outputDirectory)
        let pdfURL = try exporter.export(draft: draft, format: .pdf, to: outputDirectory)

        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        let text = try String(contentsOf: textURL, encoding: .utf8)
        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        let rtfData = try Data(contentsOf: rtfURL)
        let rtfString = try NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ).string
        let pdfSize = try FileManager.default.attributesOfItem(atPath: pdfURL.path)[.size] as? NSNumber
        let pdfDocument = try #require(PDFDocument(url: pdfURL))
        let firstPage = try #require(pdfDocument.page(at: 0))
        #expect(markdown.contains("# Project Strategy"))
        #expect(text.contains("Project Strategy"))
        #expect(text.contains("Revenue up 24%"))
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("Project Strategy"))
        #expect(html.contains("Executive Summary"))
        #expect(html.contains("Key Points"))
        #expect(html.contains("Share strategy update"))
        #expect(rtfString.contains("Project Strategy"))
        #expect(rtfString.contains("Revenue grew 24% year over year."))
        #expect(markdown.contains("## Executive Summary"))
        #expect(markdown.contains("## Key Points"))
        #expect(markdown.contains("## Result"))
        #expect(markdown.contains("Share strategy update"))
        #expect(FileManager.default.fileExists(atPath: docxURL.path))
        #expect(FileManager.default.fileExists(atPath: rtfURL.path))
        #expect(pdfSize != 0)
        #expect(pdfDocument.pageCount >= 1)
        #expect(firstPage.bounds(for: .mediaBox).width > 700)
        #expect(firstPage.bounds(for: .mediaBox).height > 1000)
    }

    @Test
    @MainActor
    func htmlExportUsesPackRendererWhenEditorDocumentIsEmpty() throws {
        let draft = DraftVersion(
            workspaceItemId: UUID(),
            goalType: .structuredNotes,
            outputLanguage: .english,
            editorDocument: "",
            structuredDoc: .fixture(
                title: "Pack Rendered Export",
                summary: "Rendered from structured content.",
                keyPoints: ["Pack-specific key point"],
                sections: [StructuredSection(title: "Overview", body: "Structured fallback body.")],
                exportMetadata: ExportMetadata(
                    contentTemplateName: "Structured Notes",
                    visualTemplateName: "Graphite",
                    preferredFormat: .html
                )
            ),
            sourceRefs: [],
            imageSuggestions: []
        )

        let html = ExportCoordinator().previewText(draft: draft, format: .html)

        #expect(html.contains("Pack Rendered Export"))
        #expect(html.contains("Pack-specific key point"))
        #expect(html.contains("--accent: #2A3347"))
    }

    @Test
    @MainActor
    func exportUsesPackStyleKitForImportedTemplates() throws {
        var pack = TemplatePackDefaults.pack(for: .technicalNote, named: "Imported Technical Template")
        pack.style = StyleKit(
            accentHex: "#2E5AAC",
            surfaceHex: "#F7F9FC",
            borderHex: "#D6E2FF",
            secondaryHex: "#5B6F9A"
        )
        let importedTemplate = Template.packBacked(pack, scope: .user)

        let draft = DraftVersion(
            workspaceItemId: UUID(),
            goalType: .structuredNotes,
            outputLanguage: .english,
            editorDocument: "",
            structuredDoc: .fixture(
                title: "Imported Export",
                summary: "Styled by the imported pack.",
                keyPoints: ["Imported pack key point"],
                exportMetadata: ExportMetadata(
                    contentTemplateID: importedTemplate.id,
                    contentTemplateName: importedTemplate.name,
                    contentTemplatePackData: importedTemplate.storedPackData,
                    visualTemplateName: "Bloom",
                    preferredFormat: .html
                )
            ),
            sourceRefs: [],
            imageSuggestions: []
        )

        let html = ExportCoordinator().previewText(draft: draft, format: .html)

        #expect(html.contains("--accent: #2E5AAC"))
        #expect(html.contains("Imported pack key point"))
    }

    @Test
    @MainActor
    func pdfExportPaginatesLongStyledPreview() throws {
        let importedTemplate = Template.packBacked(
            TemplatePackDefaults.pack(for: .technicalNote, named: "PDF Pagination Template"),
            scope: .user
        )
        let longParagraph = String(
            repeating: "这是一段为了测试 PDF 分页而重复的长内容，用来确保导出时会跨过单页高度并保持当前预览样式。 ",
            count: 12
        )

        let draft = DraftVersion(
            workspaceItemId: UUID(),
            goalType: .structuredNotes,
            outputLanguage: .chinese,
            editorDocument: "",
            structuredDoc: .fixture(
                title: "长文分页测试",
                summary: "验证 PDF 导出是否会按当前预览分页。",
                sections: (0..<48).map { index in
                    StructuredSection(
                        title: "Section \(index + 1)",
                        body: longParagraph
                    )
                },
                exportMetadata: ExportMetadata(
                    contentTemplateID: importedTemplate.id,
                    contentTemplateName: importedTemplate.name,
                    contentTemplatePackData: importedTemplate.storedPackData,
                    visualTemplateName: "Oceanic Blue",
                    preferredFormat: .pdf
                )
            ),
            sourceRefs: [],
            imageSuggestions: []
        )

        let exporter = ExportCoordinator()
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let pdfURL = try exporter.export(draft: draft, format: .pdf, to: outputDirectory)
        let pdfDocument = try #require(PDFDocument(url: pdfURL))

        #expect(pdfDocument.pageCount > 1)
        #expect(pdfDocument.page(at: 0)?.bounds(for: .mediaBox).width == 794)
        #expect(pdfDocument.page(at: 0)?.bounds(for: .mediaBox).height == 1123)
    }

    @Test
    func providerPromptIncludesGenerationHintAndRequestedBlocks() {
        let template = Template.builtinContentTemplate(named: "Action Items", goalType: .actionItems)
        let guidance = providerPromptTemplateGuidance(
            template: template,
            usedBlocks: [.actionItems, .sections]
        )

        #expect(guidance.contains("Next Steps"))
        #expect(guidance.contains("actionItems"))
    }

    @Test
    func providerPromptDescribesImportedTemplateBoxBuckets() {
        let pack = TemplatePack(
            identity: TemplatePackIdentity(name: "Graph Notes", description: "Imported from LaTeX"),
            archetype: .technicalNote,
            schema: RecommendedSchema(fields: []),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(
                    blockType: .summary,
                    fieldBinding: "summary_boxes",
                    styleVariant: TemplateBlockStyleVariant.summary.rawValue,
                    emptyBehavior: .hidden
                ),
                TemplateBlockSpec(
                    blockType: .warningBox,
                    fieldBinding: "warning_boxes",
                    styleVariant: TemplateBlockStyleVariant.warning.rawValue,
                    emptyBehavior: .hidden
                ),
                TemplateBlockSpec(
                    blockType: .callouts,
                    fieldBinding: "code_boxes",
                    styleVariant: TemplateBlockStyleVariant.code.rawValue,
                    emptyBehavior: .hidden
                ),
                TemplateBlockSpec(
                    blockType: .section,
                    fieldBinding: "sections",
                    styleVariant: TemplateBlockStyleVariant.standard.rawValue,
                    emptyBehavior: .hidden
                ),
            ]),
            style: StyleKit(accentHex: "#2E5AAC"),
            behavior: TemplateBehaviorRules()
        )
        let template = Template.packBacked(pack, scope: .user)

        let guidance = providerPromptTemplateGuidance(template: template, usedBlocks: [])

        #expect(guidance.contains("Pack layout order: summary_boxes, warning_boxes, code_boxes, sections"))
        #expect(guidance.contains("Use templateBoxes"))
        #expect(guidance.contains("critical cautions"))
        #expect(guidance.contains("commands, code snippets"))
    }
}
