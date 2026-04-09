import Testing
@testable import NotesCurator

struct TemplatePackRenderingTests {
    @Test
    func warningBlockHidesInExportWhenNoWarningsExist() throws {
        var pack = TemplatePackDefaults.pack(for: .technicalNote, named: "Lecture Notes")
        pack.layout.blocks = [
            TemplateBlockSpec(
                blockType: .warningBox,
                fieldBinding: "warnings",
                emptyBehavior: .hidden
            )
        ]
        let document = StructuredDocument.fixture(callouts: [])

        let rendered = try TemplatePackRenderer.render(document: document, pack: pack, surface: .export)
        #expect(rendered.blocks.contains(where: { $0.blockType == .warningBox }) == false)
    }

    @Test
    func authoringPreviewShowsPlaceholderForEmptyOptionalExerciseBlock() throws {
        var pack = TemplatePackDefaults.pack(for: .technicalNote, named: "Lecture Notes")
        pack.layout.blocks = [
            TemplateBlockSpec(
                blockType: .exercise,
                fieldBinding: "review_questions",
                emptyBehavior: .placeholder
            )
        ]
        let document = StructuredDocument.fixture(reviewQuestions: [])

        let rendered = try TemplatePackRenderer.render(document: document, pack: pack, surface: .authoring)
        #expect(rendered.blocks.contains(where: { $0.blockType == .exercise && $0.placeholderText != nil }))
    }

    @Test
    func codeBoxBindingRendersTemplateBoxes() throws {
        var pack = TemplatePackDefaults.pack(for: .technicalNote, named: "Imported Notes")
        pack.layout.blocks = [
            TemplateBlockSpec(
                blockType: .callouts,
                fieldBinding: "code_boxes",
                titleOverride: "Code Box",
                styleVariant: TemplateBlockStyleVariant.code.rawValue,
                emptyBehavior: .hidden
            )
        ]
        let document = StructuredDocument.fixture(
            templateBoxes: [
                StructuredTemplateBox(
                    kind: .code,
                    title: "Install Command",
                    body: "npm install @graphprotocol/graph-cli"
                )
            ]
        )

        let rendered = try TemplatePackRenderer.render(document: document, pack: pack, surface: .export)
        #expect(rendered.blocks.count == 1)
        #expect(rendered.blocks.first?.title == "Install Command")
        #expect(rendered.blocks.first?.styleVariant == TemplateBlockStyleVariant.code.rawValue)
    }

    @Test
    func summaryBoxBindingFallsBackToDocumentSummary() throws {
        var pack = TemplatePackDefaults.pack(for: .technicalNote, named: "Imported Notes")
        pack.layout.blocks = [
            TemplateBlockSpec(
                blockType: .summary,
                fieldBinding: "summary_boxes",
                titleOverride: "Summary Box",
                styleVariant: TemplateBlockStyleVariant.summary.rawValue,
                emptyBehavior: .hidden
            )
        ]
        let document = StructuredDocument.fixture(
            summary: "The imported summary should still render even without an explicit summary box."
        )

        let rendered = try TemplatePackRenderer.render(document: document, pack: pack, surface: .preview)
        #expect(rendered.blocks.count == 1)
        #expect(rendered.blocks.first?.body == "The imported summary should still render even without an explicit summary box.")
    }
}
