import Testing
@testable import NotesCurator

struct TemplateRenderingTests {
    @Test
    func builtinContentTemplatesUseTemplateSpecificNativeSampleKeys() throws {
        let expectations: [(String, GoalType, String)] = [
            ("Quick Summary", .summary, "quick_summary"),
            ("Structured Notes", .structuredNotes, "structured_notes"),
            ("Lecture Notes", .structuredNotes, "lecture_notes"),
            ("Study Guide", .structuredNotes, "study_guide"),
            ("Technical Deep Dive", .formalDocument, "technical_deep_dive"),
            ("Formal Document", .formalDocument, "formal_brief"),
        ]

        for (name, goal, sampleKey) in expectations {
            let template = try #require(Template.builtinContentTemplate(named: name, goalType: goal))
            #expect(template.defaultSampleDataKey == sampleKey)
        }
    }

    @Test
    func builtinContentTemplatesUseRealLatexSourcesInsteadOfMetadataDirectives() throws {
        let templates = Template.builtinContentTemplates

        #expect(templates.count == 6)
        #expect(templates.allSatisfy { $0.format == .latexProject })
        #expect(templates.allSatisfy { $0.storedLatexProjectData != nil })
        #expect(templates.allSatisfy {
            let source = $0.latexAuthoringSource ?? ""
            return source.contains("% notescurator.block:") == false &&
                source.contains("% notescurator.field:") == false &&
                source.contains("% notescurator.color.") == false
        })

        let formal = try #require(templates.first(where: { $0.name == "Formal Document" }))
        #expect(formal.latexAuthoringSource?.contains("\\begin{StandardBox}{Document Metadata}") == true)
        #expect(formal.latexAuthoringSource?.contains("\\begin{SummaryBox}{Executive Summary}") == true)
        #expect(formal.latexAuthoringSource?.contains("{{notescurator.summary_boxes}}") == true)
        #expect(formal.latexAuthoringSource?.contains("{{notescurator.sections}}") == true)
        #expect(formal.latexAuthoringSource?.contains("\\tableofcontents") == true)
        #expect(formal.latexAuthoringSource?.contains("\\begin{ExamBox}{Questions for Review}") == true)
        #expect(formal.latexAuthoringSource?.contains("\\begin{ResultBox}{Recommendations and Next Steps}") == true)
    }

    @Test
    func builtinTemplatePreviewSamplesRenderNativeBoxTitlesWithoutLegacyFallbacks() throws {
        let expectations: [(String, GoalType, [String])] = [
            (
                "Quick Summary",
                .summary,
                ["One-Sentence Summary", "Most Important Ideas", "Formula Snapshot", "Mistakes to Avoid", "Final Takeaway"]
            ),
            (
                "Structured Notes",
                .structuredNotes,
                ["Document Scope", "Key Insight", "Important Note", "Application", "Clarification", "Section Summary"]
            ),
            (
                "Lecture Notes",
                .structuredNotes,
                ["Lecture Overview", "Core Idea", "Definition", "Example", "Common Mistake", "Exam Tip", "Review Checklist", "Quick Recap"]
            ),
            (
                "Study Guide",
                .structuredNotes,
                ["What This Study Guide Covers", "Must-Know Concepts", "Formula Set", "Most Common Mistakes", "Short Answer Practice", "Revision Checklist", "Before the Exam"]
            ),
            (
                "Technical Deep Dive",
                .formalDocument,
                ["Primary Goal", "One-Sentence Core Insight", "System Box", "Implementation Outline", "Things That Commonly Go Wrong", "Edge Cases to Consider", "Ultimate Summary"]
            ),
            (
                "Formal Document",
                .formalDocument,
                ["Document Metadata", "Executive Summary", "Key Insight", "Scope", "Risks and Warnings", "Reference Snippet", "Questions for Review", "Recommendations and Next Steps"]
            ),
        ]

        for (name, goal, titles) in expectations {
            let rendered = try previewRenderedDocument(templateNamed: name, goalType: goal)
            let renderedTitles = Set(rendered.blocks.map(\.title))

            for title in titles {
                #expect(renderedTitles.contains(title))
            }

            #expect(rendered.blocks.allSatisfy { $0.placeholderText == nil })
            #expect(renderedTitles.contains("Summary") == false)
            #expect(renderedTitles.contains("Key Points") == false)
            #expect(renderedTitles.contains("Questions") == false)
            #expect(renderedTitles.contains("Checklist") == false)
            #expect(renderedTitles.contains("Result") == false)
        }
    }

    @Test
    func parsesFrontMatterAndExposesGoalGenerationHintAndSampleKey() throws {
        let parsed = try MarkdownTemplate.parse("""
        ---
        goal: actionItems
        generation_hint: |
          Put next steps early.
        sample_data: action_plan
        ---
        # {{title}}
        """)

        #expect(parsed.frontMatter.goal == .actionItems)
        #expect(parsed.frontMatter.sampleDataKey == "action_plan")
        #expect(parsed.frontMatter.generationHint.contains("next steps"))
    }

    @Test
    func rendersConditionalAndRepeatedBlocks() throws {
        let rendered = try MarkdownTemplateRenderer.render(
            template: try MarkdownTemplate.parse("""
            # {{title}}
            {{#if actionItems}}
            ## Next Steps
            {{#each actionItems}}
            - {{item}}
            {{/each}}
            {{/if}}
            """),
            document: .actionPlanSample
        )

        #expect(rendered.contains("## Next Steps"))
        #expect(rendered.contains("- Assign owners"))
    }

    @Test
    func rejectsUnknownTokens() {
        #expect(throws: MarkdownTemplateError.unsupportedToken("foobar")) {
            try MarkdownTemplate.parse("# {{foobar}}")
        }
    }

    @Test
    func differentTemplatesProduceDifferentLayoutsFromSameData() throws {
        let action = try MarkdownTemplateRenderer.render(
            template: try MarkdownTemplate.parse("""
            ## Next Steps
            {{#each actionItems}}
            - {{item}}
            {{/each}}
            ## Details
            {{#each sections}}
            ### {{title}}
            {{body}}
            {{/each}}
            """),
            document: .actionPlanSample
        )
        let brief = try MarkdownTemplateRenderer.render(
            template: try MarkdownTemplate.parse("""
            ## Context
            {{#each sections}}
            ### {{title}}
            {{body}}
            {{/each}}
            ## Actions
            {{#each actionItems}}
            - {{item}}
            {{/each}}
            """),
            document: .actionPlanSample
        )

        #expect(action != brief)
    }

    private func previewRenderedDocument(templateNamed name: String, goalType: GoalType) throws -> RenderedTemplateDocument {
        let template = try #require(Template.builtinContentTemplate(named: name, goalType: goalType))
        let pack = try template.templatePack()
        var document = TemplatePreviewSamples.document(for: template.defaultSampleDataKey, fallbackGoal: template.configuredGoalType)
        document.exportMetadata.contentTemplateID = template.id
        document.exportMetadata.contentTemplateName = template.name
        document.exportMetadata.contentTemplatePackData = template.storedPackData
        document.exportMetadata.contentTemplateLatexProjectData = template.storedLatexProjectData
        document.exportMetadata.renderedContentTemplateID = template.id
        document.exportMetadata.visualTemplateName = "Oceanic Blue"
        document.exportMetadata.preferredFormat = .pdf

        let editorDocument = try TemplatePackMarkdownEmitter.emit(document: document, pack: pack, surface: .authoring)
        let preview = DraftVersion.previewDraft(
            document: document,
            goalType: template.configuredGoalType,
            editorDocument: editorDocument
        )
        return try preview.renderedTemplateDocument(for: .preview)
    }
}
