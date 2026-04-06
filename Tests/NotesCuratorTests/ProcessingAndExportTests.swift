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
        #expect(draft.editorDocument.contains("摘要"))
        #expect(draft.imageSuggestions.count == 1)
        #expect(draft.imageSuggestions.first?.title == "Budget Slide")
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
        #expect(draft.editorDocument.contains("Validated by repair"))
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
        #expect(draft.editorDocument.contains("Validated by repair"))
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
            editorDocument: "Executive Summary\nRevenue grew 24% year over year.",
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
        #expect(html.contains("Main takeaway"))
        #expect(rtfString.contains("Project Strategy"))
        #expect(rtfString.contains("Growth came without operational sprawl."))
        #expect(markdown.contains("## Cue Questions"))
        #expect(markdown.contains("## Glossary"))
        #expect(markdown.contains("## Study Cards"))
        #expect(markdown.contains("Q: What explains the revenue growth?"))
        #expect(markdown.contains("## Review Questions"))
        #expect(markdown.contains("## Callouts"))
        #expect(FileManager.default.fileExists(atPath: docxURL.path))
        #expect(FileManager.default.fileExists(atPath: rtfURL.path))
        #expect(pdfSize != 0)
        #expect(pdfDocument.pageCount >= 1)
        #expect(firstPage.bounds(for: .mediaBox).width > 700)
        #expect(firstPage.bounds(for: .mediaBox).height > 1000)
    }
}
