import Testing
@testable import NotesCurator

struct TemplateRenderingTests {
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
}
