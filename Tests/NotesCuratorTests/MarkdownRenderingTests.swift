import Testing
@testable import NotesCurator

struct MarkdownRenderingTests {
    @Test
    func packMarkdownEmitterProducesStableSectionOrdering() throws {
        let pack = TemplatePackDefaults.pack(for: .technicalNote, named: "Lecture Notes")
        let rendered = try TemplatePackRenderer.render(
            document: .fixture(
                title: "Pack Export",
                summary: "A concise summary.",
                keyPoints: ["First point"],
                sections: [StructuredSection(title: "Overview", body: "Detailed context.")],
                reviewQuestions: ["What matters most?"]
            ),
            pack: pack,
            surface: .export
        )

        let markdown = TemplatePackMarkdownEmitter.emit(rendered)

        #expect(markdown.contains("# Pack Export"))
        #expect(markdown.contains("## Key Points"))
        #expect(markdown.firstIndex(of: "#")! < markdown.range(of: "## Key Points")!.lowerBound)
    }

    @Test
    func parsesHeadingsParagraphsAndBulletListsInOrder() throws {
        let blocks = try MarkdownDocument.parse("""
        # Action Plan

        A task-first summary.

        ## Next Steps
        - Assign owners
        - Track deadlines
        """).blocks

        #expect(blocks.map(\.kind) == [.heading1, .paragraph, .heading2, .list])
    }

    @Test
    func htmlRendererPreservesBlockOrderFromEditorDocument() throws {
        let html = try MarkdownHTMLRenderer.render("""
        ## Next Steps
        - Assign owners

        ## Context
        Why this work matters.
        """)

        #expect(html.contains("Next Steps"))
        #expect(html.firstIndex(of: "N")! < html.firstIndex(of: "C")!)
    }
}
