import Foundation

enum TemplatePackDefaults {
    static func pack(
        for archetype: TemplateArchetype,
        named name: String,
        description: String = "",
        style: StyleKit? = nil
    ) -> TemplatePack {
        let normalizedName = normalizedTemplateName(name)

        switch archetype {
        case .technicalNote:
            if normalizedName == "summary" || normalizedName == "quick summary" {
                return summaryPack(
                    named: name,
                    description: resolvedDescription(description, fallback: "Fast condensation"),
                    style: style ?? .summaryDefault
                )
            }
            if normalizedName == "lecture notes" {
                return lectureNotesPack(
                    named: name,
                    description: resolvedDescription(description, fallback: "Teaching-first structure"),
                    style: style ?? .lectureNotesDefault
                )
            }
            if normalizedName == "structured notes" {
                return structuredNotesPack(
                    named: name,
                    description: resolvedDescription(description, fallback: "Balanced recall support"),
                    style: style ?? .structuredNotesDefault
                )
            }
            if normalizedName == "study guide" {
                return studyGuidePack(
                    named: name,
                    description: resolvedDescription(description, fallback: "Review-first format"),
                    style: style ?? .studyGuideDefault
                )
            }
            if normalizedName == "technical deep dive" {
                return technicalDeepDivePack(
                    named: name,
                    description: resolvedDescription(description, fallback: "Dense technical walkthrough"),
                    style: style ?? .technicalDeepDiveDefault
                )
            }
            return technicalNotePack(named: name, description: description, style: style ?? .technicalNoteDefault)
        case .meetingBrief:
            return meetingBriefPack(named: name, description: description, style: style ?? .meetingBriefDefault)
        case .formalBrief:
            if normalizedName == "formal document" {
                return formalDocumentPack(
                    named: name,
                    description: resolvedDescription(description, fallback: "Polished stakeholder-ready document"),
                    style: style ?? .formalDocumentDefault
                )
            }
            return formalBriefPack(named: name, description: description, style: style ?? .formalBriefDefault)
        }
    }

    static func summaryPack(
        named name: String,
        description: String = "Fast condensation",
        style: StyleKit = .summaryDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .technicalNote,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "summary_boxes", label: "One-Sentence Summary", requiredLevel: .coreRequired),
                RecommendedField(key: "key_boxes", label: "Most Important Ideas", requiredLevel: .coreRequired),
                RecommendedField(key: "sections", label: "Compressed Sections", requiredLevel: .preferredOptional),
                RecommendedField(key: "code_boxes", label: "Formula Snapshots", requiredLevel: .preferredOptional),
                RecommendedField(key: "warning_boxes", label: "Common Traps", requiredLevel: .preferredOptional),
                RecommendedField(key: "result_boxes", label: "Final Takeaways", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .summary, fieldBinding: "summary_boxes", titleOverride: "One-Sentence Summary", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_boxes", titleOverride: "Most Important Ideas", styleVariant: TemplateBlockStyleVariant.key.rawValue),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", titleOverride: "Compressed Explanation", styleVariant: TemplateBlockStyleVariant.standard.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "code_boxes", titleOverride: "Formula Snapshot", styleVariant: TemplateBlockStyleVariant.code.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .warningBox, fieldBinding: "warning_boxes", titleOverride: "Mistakes to Avoid", styleVariant: TemplateBlockStyleVariant.warning.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "result_boxes", titleOverride: "Final Takeaway", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules(followsVisualTheme: true)
        )
    }

    static func lectureNotesPack(
        named name: String,
        description: String = "Teaching-first structure",
        style: StyleKit = .lectureNotesDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .technicalNote,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "summary_boxes", label: "Lecture Overview", requiredLevel: .coreRequired),
                RecommendedField(key: "key_boxes", label: "Key Concepts", requiredLevel: .preferredOptional),
                RecommendedField(key: "sections", label: "Lecture Flow", requiredLevel: .templateRequired),
                RecommendedField(key: "explanation_boxes", label: "Definition Boxes", requiredLevel: .preferredOptional),
                RecommendedField(key: "example_boxes", label: "Example Boxes", requiredLevel: .preferredOptional),
                RecommendedField(key: "warning_boxes", label: "Common Mistakes", requiredLevel: .preferredOptional),
                RecommendedField(key: "exam_boxes", label: "Exam Tips", requiredLevel: .preferredOptional),
                RecommendedField(key: "checklist_boxes", label: "Review Checklists", requiredLevel: .preferredOptional),
                RecommendedField(key: "result_boxes", label: "Recap Boxes", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .summary, fieldBinding: "summary_boxes", titleOverride: "Lecture Overview", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_boxes", titleOverride: "Core Idea", styleVariant: TemplateBlockStyleVariant.key.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", titleOverride: "Lecture Flow", styleVariant: TemplateBlockStyleVariant.standard.rawValue),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "explanation_boxes", titleOverride: "Definition", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "example_boxes", titleOverride: "Example", styleVariant: TemplateBlockStyleVariant.standard.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .warningBox, fieldBinding: "warning_boxes", titleOverride: "Common Mistake", styleVariant: TemplateBlockStyleVariant.warning.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .exercise, fieldBinding: "exam_boxes", titleOverride: "Exam Tip", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "checklist_boxes", titleOverride: "Review Checklist", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "result_boxes", titleOverride: "Quick Recap", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules(followsVisualTheme: true)
        )
    }

    static func studyGuidePack(
        named name: String,
        description: String = "Review-first format",
        style: StyleKit = .studyGuideDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .technicalNote,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "summary_boxes", label: "Exam Focus", requiredLevel: .coreRequired),
                RecommendedField(key: "key_boxes", label: "Must-Know Concepts", requiredLevel: .preferredOptional),
                RecommendedField(key: "sections", label: "Core Relationships", requiredLevel: .templateRequired),
                RecommendedField(key: "code_boxes", label: "Formula Boxes", requiredLevel: .preferredOptional),
                RecommendedField(key: "warning_boxes", label: "Exam Traps", requiredLevel: .preferredOptional),
                RecommendedField(key: "question_boxes", label: "Practice Prompts", requiredLevel: .preferredOptional),
                RecommendedField(key: "checklist_boxes", label: "Revision Checklists", requiredLevel: .preferredOptional),
                RecommendedField(key: "result_boxes", label: "Before the Exam", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .summary, fieldBinding: "summary_boxes", titleOverride: "What This Study Guide Covers", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_boxes", titleOverride: "Must-Know Concepts", styleVariant: TemplateBlockStyleVariant.key.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", titleOverride: "Core Relationships", styleVariant: TemplateBlockStyleVariant.standard.rawValue),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "code_boxes", titleOverride: "Formula Set", styleVariant: TemplateBlockStyleVariant.code.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .warningBox, fieldBinding: "warning_boxes", titleOverride: "Most Common Mistakes", styleVariant: TemplateBlockStyleVariant.warning.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .exercise, fieldBinding: "question_boxes", titleOverride: "Short Answer Practice", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "checklist_boxes", titleOverride: "Revision Checklist", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "result_boxes", titleOverride: "Before the Exam", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules(followsVisualTheme: true)
        )
    }

    static func structuredNotesPack(
        named name: String,
        description: String = "Balanced recall support",
        style: StyleKit = .structuredNotesDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .technicalNote,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "summary_boxes", label: "Document Scope", requiredLevel: .coreRequired),
                RecommendedField(key: "key_boxes", label: "Key Insights", requiredLevel: .preferredOptional),
                RecommendedField(key: "sections", label: "Sections", requiredLevel: .templateRequired),
                RecommendedField(key: "explanation_boxes", label: "Note Boxes", requiredLevel: .preferredOptional),
                RecommendedField(key: "example_boxes", label: "Example Boxes", requiredLevel: .preferredOptional),
                RecommendedField(key: "warning_boxes", label: "Warnings", requiredLevel: .preferredOptional),
                RecommendedField(key: "result_boxes", label: "Section Summaries", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .summary, fieldBinding: "summary_boxes", titleOverride: "Document Scope", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_boxes", titleOverride: "Key Insight", styleVariant: TemplateBlockStyleVariant.key.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", styleVariant: TemplateBlockStyleVariant.standard.rawValue),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "explanation_boxes", titleOverride: "Important Note", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "example_boxes", titleOverride: "Application", styleVariant: TemplateBlockStyleVariant.standard.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .warningBox, fieldBinding: "warning_boxes", titleOverride: "Clarification", styleVariant: TemplateBlockStyleVariant.warning.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "result_boxes", titleOverride: "Section Summary", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules(followsVisualTheme: true)
        )
    }

    static func technicalDeepDivePack(
        named name: String,
        description: String = "Dense technical walkthrough",
        style: StyleKit = .technicalDeepDiveDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .technicalNote,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "summary_boxes", label: "Primary Goal", requiredLevel: .coreRequired),
                RecommendedField(key: "key_boxes", label: "Core Insights", requiredLevel: .preferredOptional),
                RecommendedField(key: "sections", label: "Execution Flow", requiredLevel: .templateRequired),
                RecommendedField(key: "explanation_boxes", label: "System Boxes", requiredLevel: .preferredOptional),
                RecommendedField(key: "code_boxes", label: "Implementation Notes", requiredLevel: .preferredOptional),
                RecommendedField(key: "warning_boxes", label: "Pitfalls", requiredLevel: .preferredOptional),
                RecommendedField(key: "example_boxes", label: "Edge Cases", requiredLevel: .preferredOptional),
                RecommendedField(key: "result_boxes", label: "Final Takeaways", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .summary, fieldBinding: "summary_boxes", titleOverride: "Primary Goal", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_boxes", titleOverride: "One-Sentence Core Insight", styleVariant: TemplateBlockStyleVariant.key.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "explanation_boxes", titleOverride: "System Box", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", titleOverride: "Deep Dive", styleVariant: TemplateBlockStyleVariant.standard.rawValue),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "code_boxes", titleOverride: "Implementation Outline", styleVariant: TemplateBlockStyleVariant.code.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .warningBox, fieldBinding: "warning_boxes", titleOverride: "Things That Commonly Go Wrong", styleVariant: TemplateBlockStyleVariant.warning.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .exercise, fieldBinding: "example_boxes", titleOverride: "Edge Cases to Consider", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "result_boxes", titleOverride: "Ultimate Summary", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules(followsVisualTheme: true)
        )
    }

    static func formalDocumentPack(
        named name: String,
        description: String = "Polished stakeholder-ready document",
        style: StyleKit = .formalDocumentDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .formalBrief,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "meta_boxes", label: "Document Metadata", requiredLevel: .preferredOptional),
                RecommendedField(key: "summary_boxes", label: "Executive Summary", requiredLevel: .coreRequired),
                RecommendedField(key: "key_boxes", label: "Key Insight", requiredLevel: .preferredOptional),
                RecommendedField(key: "sections", label: "Main Body", requiredLevel: .templateRequired),
                RecommendedField(key: "explanation_boxes", label: "Scope and Context", requiredLevel: .preferredOptional),
                RecommendedField(key: "warning_boxes", label: "Risks", requiredLevel: .preferredOptional),
                RecommendedField(key: "code_boxes", label: "Reference Snippets", requiredLevel: .preferredOptional),
                RecommendedField(key: "question_boxes", label: "Review Questions", requiredLevel: .preferredOptional),
                RecommendedField(key: "result_boxes", label: "Recommendations", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "meta_boxes", titleOverride: "Document Metadata", styleVariant: TemplateBlockStyleVariant.standard.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .summary, fieldBinding: "summary_boxes", titleOverride: "Executive Summary", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_boxes", titleOverride: "Key Insight", styleVariant: TemplateBlockStyleVariant.key.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "explanation_boxes", titleOverride: "Scope", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", styleVariant: TemplateBlockStyleVariant.standard.rawValue),
                TemplateBlockSpec(blockType: .warningBox, fieldBinding: "warning_boxes", titleOverride: "Risks and Warnings", styleVariant: TemplateBlockStyleVariant.warning.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "code_boxes", titleOverride: "Reference Snippet", styleVariant: TemplateBlockStyleVariant.code.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .exercise, fieldBinding: "question_boxes", titleOverride: "Questions for Review", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "result_boxes", titleOverride: "Recommendations and Next Steps", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules(followsVisualTheme: true)
        )
    }

    static func technicalNotePack(
        named name: String,
        description: String = "",
        style: StyleKit = .technicalNoteDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .technicalNote,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "overview", label: "Overview", requiredLevel: .coreRequired),
                RecommendedField(key: "cue_questions", label: "Cue Questions", requiredLevel: .preferredOptional),
                RecommendedField(key: "key_points", label: "Key Points", requiredLevel: .coreRequired),
                RecommendedField(key: "sections", label: "Sections", requiredLevel: .templateRequired),
                RecommendedField(key: "callouts", label: "Callouts", requiredLevel: .preferredOptional),
                RecommendedField(key: "warnings", label: "Warnings", requiredLevel: .preferredOptional),
                RecommendedField(key: "glossary", label: "Glossary", requiredLevel: .preferredOptional),
                RecommendedField(key: "study_cards", label: "Study Cards", requiredLevel: .preferredOptional),
                RecommendedField(key: "review_questions", label: "Review Questions", requiredLevel: .preferredOptional),
                RecommendedField(key: "action_items", label: "Action Items", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .summary, fieldBinding: "overview", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .cueQuestions, fieldBinding: "cue_questions", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_points", styleVariant: TemplateBlockStyleVariant.key.rawValue),
                TemplateBlockSpec(blockType: .warningBox, fieldBinding: "warnings", styleVariant: TemplateBlockStyleVariant.warning.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", styleVariant: TemplateBlockStyleVariant.standard.rawValue),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "callouts", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .glossary, fieldBinding: "glossary", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .studyCards, fieldBinding: "study_cards", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .reviewQuestions, fieldBinding: "review_questions", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "action_items", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules()
        )
    }

    static func meetingBriefPack(
        named name: String,
        description: String = "",
        style: StyleKit = .meetingBriefDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .meetingBrief,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "overview", label: "Overview", requiredLevel: .coreRequired),
                RecommendedField(key: "key_points", label: "Key Points", requiredLevel: .preferredOptional),
                RecommendedField(key: "sections", label: "Sections", requiredLevel: .templateRequired),
                RecommendedField(key: "callouts", label: "Callouts", requiredLevel: .preferredOptional),
                RecommendedField(key: "action_items", label: "Action Items", requiredLevel: .coreRequired),
                RecommendedField(key: "review_questions", label: "Review Questions", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .summary, fieldBinding: "overview", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "action_items", styleVariant: TemplateBlockStyleVariant.result.rawValue),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_points", styleVariant: TemplateBlockStyleVariant.key.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", styleVariant: TemplateBlockStyleVariant.standard.rawValue),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "callouts", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .reviewQuestions, fieldBinding: "review_questions", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules()
        )
    }

    static func formalBriefPack(
        named name: String,
        description: String = "",
        style: StyleKit = .formalBriefDefault
    ) -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(name: name, description: description),
            archetype: .formalBrief,
            schema: RecommendedSchema(fields: [
                RecommendedField(key: "overview", label: "Overview", requiredLevel: .coreRequired),
                RecommendedField(key: "cue_questions", label: "Cue Questions", requiredLevel: .preferredOptional),
                RecommendedField(key: "key_points", label: "Key Points", requiredLevel: .preferredOptional),
                RecommendedField(key: "sections", label: "Sections", requiredLevel: .templateRequired),
                RecommendedField(key: "callouts", label: "Callouts", requiredLevel: .preferredOptional),
                RecommendedField(key: "glossary", label: "Glossary", requiredLevel: .preferredOptional),
                RecommendedField(key: "study_cards", label: "Study Cards", requiredLevel: .preferredOptional),
                RecommendedField(key: "review_questions", label: "Review Questions", requiredLevel: .preferredOptional),
                RecommendedField(key: "action_items", label: "Action Items", requiredLevel: .preferredOptional),
            ]),
            layout: LayoutSpec(blocks: [
                TemplateBlockSpec(blockType: .summary, fieldBinding: "overview", styleVariant: TemplateBlockStyleVariant.summary.rawValue),
                TemplateBlockSpec(blockType: .cueQuestions, fieldBinding: "cue_questions", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .keyPoints, fieldBinding: "key_points", styleVariant: TemplateBlockStyleVariant.key.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .section, fieldBinding: "sections", styleVariant: TemplateBlockStyleVariant.standard.rawValue),
                TemplateBlockSpec(blockType: .callouts, fieldBinding: "callouts", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .glossary, fieldBinding: "glossary", styleVariant: TemplateBlockStyleVariant.summary.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .studyCards, fieldBinding: "study_cards", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .reviewQuestions, fieldBinding: "review_questions", styleVariant: TemplateBlockStyleVariant.exam.rawValue, emptyBehavior: .hidden),
                TemplateBlockSpec(blockType: .actionItems, fieldBinding: "action_items", styleVariant: TemplateBlockStyleVariant.result.rawValue, emptyBehavior: .hidden),
            ]),
            style: style,
            behavior: TemplateBehaviorRules()
        )
    }

    static func importedPack(
        archetype: TemplateArchetype,
        fingerprint: SourceFingerprint,
        suggestedName: String
    ) -> TemplatePack {
        var pack = pack(
            for: archetype,
            named: suggestedName,
            description: "Imported from LaTeX"
        )
        let importedLayout = importedLayout(from: fingerprint)
        if !importedLayout.blocks.isEmpty {
            pack.layout = importedLayout
            pack.schema = importedSchema(for: importedLayout)
        }

        pack.style = StyleKit(
            accentHex: fingerprint.palette.accentHex,
            surfaceHex: fingerprint.palette.surfaceHex ?? pack.style.surfaceHex,
            borderHex: pack.style.borderHex,
            secondaryHex: pack.style.secondaryHex,
            boxStyles: pack.style.boxStyles
        )
        pack.behavior.followsVisualTheme = false

        // Imported templates should behave like the source layout:
        // if a box has matching content we render it, otherwise we omit it.
        pack.layout.blocks = pack.layout.blocks.map { block in
            var copy = block
            copy.emptyBehavior = .hidden
            return copy
        }

        return pack
    }
}

extension TemplatePackDefaults {
    static func semanticThemedStyle(
        theme: DocumentTheme,
        preserving baseStyle: StyleKit
    ) -> StyleKit {
        let adaptiveStyles = StyleKit.defaultBoxStyles(
            accentHex: theme.accentHex,
            surfaceHex: theme.surfaceHex,
            borderHex: theme.borderHex,
            secondaryHex: theme.secondaryHex
        )
        let adaptiveByVariant = Dictionary(uniqueKeysWithValues: adaptiveStyles.map { ($0.variant, $0) })
        var mergedByVariant = Dictionary(uniqueKeysWithValues: baseStyle.boxStyles.map { ($0.variant, $0) })

        for variant in [TemplateBlockStyleVariant.standard, .summary, .key, .exam] {
            if let adaptive = adaptiveByVariant[variant] {
                mergedByVariant[variant] = adaptive
            }
        }

        for variant in TemplateBlockStyleVariant.allCases where mergedByVariant[variant] == nil {
            mergedByVariant[variant] = adaptiveByVariant[variant]
        }

        return StyleKit(
            accentHex: theme.accentHex,
            surfaceHex: theme.surfaceHex,
            borderHex: theme.borderHex,
            secondaryHex: theme.secondaryHex,
            boxStyles: TemplateBlockStyleVariant.allCases.compactMap { mergedByVariant[$0] }
        )
    }
}

private extension TemplatePackDefaults {
    static func normalizedTemplateName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func resolvedDescription(_ description: String, fallback: String) -> String {
        description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : description
    }

    static func importedLayout(from fingerprint: SourceFingerprint) -> LayoutSpec {
        var blocks: [TemplateBlockSpec] = []
        var seenBindings: Set<String> = []

        for boxStyle in fingerprint.boxStyles {
            guard let block = importedBlock(for: boxStyle),
                  let binding = block.fieldBinding,
                  seenBindings.insert(binding).inserted else {
                continue
            }
            blocks.append(block)
        }

        if seenBindings.insert("sections").inserted {
            blocks.append(
                TemplateBlockSpec(
                    blockType: .section,
                    fieldBinding: "sections",
                    titleOverride: "Sections",
                    styleVariant: TemplateBlockStyleVariant.standard.rawValue,
                    emptyBehavior: .hidden
                )
            )
        }

        return LayoutSpec(blocks: blocks)
    }

    static func importedSchema(for layout: LayoutSpec) -> RecommendedSchema {
        RecommendedSchema(
            fields: layout.blocks.compactMap { block in
                guard let binding = block.fieldBinding else { return nil }
                return RecommendedField(
                    key: binding,
                    label: importedFieldLabel(for: binding),
                    requiredLevel: importedFieldRequirement(for: binding)
                )
            }
        )
    }

    static func importedBlock(for style: LatexBoxStyle) -> TemplateBlockSpec? {
        guard let mapping = importedBoxMapping(for: style) else { return nil }
        return TemplateBlockSpec(
            blockType: mapping.blockType,
            fieldBinding: mapping.binding,
            titleOverride: preferredImportedTitle(for: style),
            styleVariant: mapping.variant.rawValue,
            emptyBehavior: .hidden
        )
    }

    static func importedBoxMapping(
        for style: LatexBoxStyle
    ) -> (binding: String, blockType: TemplateBlockType, variant: TemplateBlockStyleVariant)? {
        let combined = "\(style.name) \(style.title ?? "")"
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        if combined.contains("warning") || combined.contains("caution") || combined.contains("pitfall") {
            return ("warning_boxes", .warningBox, .warning)
        }
        if combined.contains("metadata") || combined.contains("document data") || combined.contains("meta") {
            return ("meta_boxes", .callouts, .standard)
        }
        if combined.contains("result") || combined.contains("checklist") || combined.contains("prerequisite") || combined.contains("success") {
            if combined.contains("checklist") || combined.contains("prerequisite") {
                return ("checklist_boxes", .actionItems, .result)
            }
            return ("result_boxes", .actionItems, .result)
        }
        if combined.contains("code") || combined.contains("command") || combined.contains("snippet") || combined.contains("query") || combined.contains("ascii") || combined.contains("config") {
            return ("code_boxes", .callouts, .code)
        }
        if combined.contains("exam") || combined.contains("exercise") || combined.contains("quiz") || combined.contains("q&a") || combined.contains("qa") || combined.contains("interview") || combined.contains("self check") || combined.contains("self-check") {
            if combined.contains("question") || combined.contains("q&a") || combined.contains("qa") || combined.contains("interview") {
                return ("question_boxes", .exercise, .exam)
            }
            return ("exam_boxes", .exercise, .exam)
        }
        if combined.contains("explanation") || combined.contains("explainer") || combined.contains("note") {
            return ("explanation_boxes", .callouts, .summary)
        }
        if combined.contains("example") || combined.contains("scenario") || combined.contains("case study") {
            return ("example_boxes", .callouts, .standard)
        }
        if combined.contains("key") || combined.contains("takeaway") || combined.contains("highlight") || combined.contains("concept") {
            return ("key_boxes", .keyPoints, .key)
        }
        if combined.contains("summary") || combined.contains("overview") || combined.contains("recap") {
            return ("summary_boxes", .summary, .summary)
        }
        return nil
    }

    static func preferredImportedTitle(for style: LatexBoxStyle) -> String {
        if let explicitTitle = style.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitTitle.isEmpty,
           explicitTitle.contains("#") == false,
           explicitTitle.contains("\\") == false {
            return explicitTitle
        }

        var rawName = style.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawName.hasSuffix("Box") {
            rawName.removeLast(3)
        }

        let withSpaces = rawName.unicodeScalars.reduce(into: "") { partial, scalar in
            let character = Character(scalar)
            if character.isUppercase, !partial.isEmpty, partial.last?.isWhitespace == false {
                partial.append(" ")
            }
            partial.append(character)
        }

        let title = withSpaces.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? style.name : title
    }

    static func importedFieldLabel(for binding: String) -> String {
        switch binding {
        case "summary_boxes":
            return "Summary Boxes"
        case "key_boxes":
            return "Key Boxes"
        case "meta_boxes":
            return "Metadata Boxes"
        case "warning_boxes":
            return "Warning Boxes"
        case "code_boxes":
            return "Code Boxes"
        case "result_boxes":
            return "Result Boxes"
        case "exam_boxes":
            return "Exam Boxes"
        case "checklist_boxes":
            return "Checklist Boxes"
        case "question_boxes":
            return "Question Boxes"
        case "explanation_boxes":
            return "Explanation Boxes"
        case "example_boxes":
            return "Example Boxes"
        case "sections":
            return "Sections"
        default:
            return binding
        }
    }

    static func importedFieldRequirement(for binding: String) -> TemplateFieldRequiredLevel {
        switch binding {
        case "summary_boxes":
            return .coreRequired
        case "sections":
            return .templateRequired
        default:
            return .preferredOptional
        }
    }
}

extension StyleKit {
    static let technicalNoteDefault = StyleKit(
        accentHex: "#2E5AAC",
        surfaceHex: "#F6F9FF",
        borderHex: "#D6E2FF",
        secondaryHex: "#5B6F9A",
        boxStyles: defaultBoxStyles(
            accentHex: "#2E5AAC",
            surfaceHex: "#F6F9FF",
            borderHex: "#D6E2FF",
            secondaryHex: "#5B6F9A"
        )
    )

    static let meetingBriefDefault = StyleKit(
        accentHex: "#2F6A57",
        surfaceHex: "#F4FBF7",
        borderHex: "#D2E9DD",
        secondaryHex: "#5C7A70",
        boxStyles: defaultBoxStyles(
            accentHex: "#2F6A57",
            surfaceHex: "#F4FBF7",
            borderHex: "#D2E9DD",
            secondaryHex: "#5C7A70"
        )
    )

    static let formalBriefDefault = StyleKit(
        accentHex: "#7A5C2E",
        surfaceHex: "#FFFCF7",
        borderHex: "#E8D9BD",
        secondaryHex: "#8B7756",
        boxStyles: defaultBoxStyles(
            accentHex: "#7A5C2E",
            surfaceHex: "#FFFCF7",
            borderHex: "#E8D9BD",
            secondaryHex: "#8B7756"
        )
    )

    static let lectureNotesDefault = StyleKit(
        accentHex: "#3D5A80",
        surfaceHex: "#EAF2FB",
        borderHex: "#D6E2F0",
        secondaryHex: "#6E7D94",
        boxStyles: defaultBoxStyles(
            accentHex: "#3D5A80",
            surfaceHex: "#EAF2FB",
            borderHex: "#D6E2F0",
            secondaryHex: "#6E7D94"
        )
    )

    static let summaryDefault = StyleKit(
        accentHex: "#2E5AAC",
        surfaceHex: "#F5F7FB",
        borderHex: "#D6DEEE",
        secondaryHex: "#5B6573",
        boxStyles: {
            var styles = defaultBoxStyles(
                accentHex: "#2E5AAC",
                surfaceHex: "#F5F7FB",
                borderHex: "#D6DEEE",
                secondaryHex: "#5B6573"
            )
            if let index = styles.firstIndex(where: { $0.variant == .code }) {
                styles[index] = TemplateBoxStyle(
                    variant: .code,
                    borderHex: "#4F8A63",
                    backgroundHex: "#EEF8F2",
                    titleBackgroundHex: "#DFF0E5",
                    titleTextHex: "#2E6A40",
                    bodyTextHex: "#1F3D2A"
                )
            }
            if let index = styles.firstIndex(where: { $0.variant == .result }) {
                styles[index] = TemplateBoxStyle(
                    variant: .result,
                    borderHex: "#2E5AAC",
                    backgroundHex: "#EEF4FF",
                    titleBackgroundHex: "#DDE8FF",
                    titleTextHex: "#234985",
                    bodyTextHex: "#1E2A36"
                )
            }
            return styles
        }()
    )

    static let structuredNotesDefault = StyleKit(
        accentHex: "#2F4858",
        surfaceHex: "#F7F9FC",
        borderHex: "#D9E2EC",
        secondaryHex: "#6B7280",
        boxStyles: defaultBoxStyles(
            accentHex: "#2F4858",
            surfaceHex: "#F7F9FC",
            borderHex: "#D9E2EC",
            secondaryHex: "#6B7280"
        )
    )

    static let studyGuideDefault = StyleKit(
        accentHex: "#2E5AAC",
        surfaceHex: "#F5F7FB",
        borderHex: "#D6DEEE",
        secondaryHex: "#5B6573",
        boxStyles: {
            var styles = defaultBoxStyles(
                accentHex: "#2E5AAC",
                surfaceHex: "#F5F7FB",
                borderHex: "#D6DEEE",
                secondaryHex: "#5B6573"
            )
            if let index = styles.firstIndex(where: { $0.variant == .code }) {
                styles[index] = TemplateBoxStyle(
                    variant: .code,
                    borderHex: "#4F8A63",
                    backgroundHex: "#EEF8F2",
                    titleBackgroundHex: "#DFF0E5",
                    titleTextHex: "#2E6A40",
                    bodyTextHex: "#1F3D2A"
                )
            }
            if let index = styles.firstIndex(where: { $0.variant == .result }) {
                styles[index] = TemplateBoxStyle(
                    variant: .result,
                    borderHex: "#C98E22",
                    backgroundHex: "#FFF8E8",
                    titleBackgroundHex: "#F8EAC0",
                    titleTextHex: "#8A6110",
                    bodyTextHex: "#4A3920"
                )
            }
            return styles
        }()
    )

    static let formalDocumentDefault = StyleKit(
        accentHex: "#294C60",
        surfaceHex: "#FAFBFC",
        borderHex: "#D9D9D9",
        secondaryHex: "#666666",
        boxStyles: defaultBoxStyles(
            accentHex: "#294C60",
            surfaceHex: "#FAFBFC",
            borderHex: "#D9D9D9",
            secondaryHex: "#666666"
        )
    )

    static let technicalDeepDiveDefault = StyleKit(
        accentHex: "#2E5AAC",
        surfaceHex: "#F5F7FB",
        borderHex: "#D6DEEE",
        secondaryHex: "#5B6573",
        boxStyles: {
            var styles = defaultBoxStyles(
                accentHex: "#2E5AAC",
                surfaceHex: "#F5F7FB",
                borderHex: "#D6DEEE",
                secondaryHex: "#5B6573"
            )
            if let index = styles.firstIndex(where: { $0.variant == .code }) {
                styles[index] = TemplateBoxStyle(
                    variant: .code,
                    borderHex: "#D9DFEA",
                    backgroundHex: "#F8F9FC",
                    titleBackgroundHex: "#EEF1F6",
                    titleTextHex: "#5B6573",
                    bodyTextHex: "#1E2A36"
                )
            }
            if let index = styles.firstIndex(where: { $0.variant == .result }) {
                styles[index] = TemplateBoxStyle(
                    variant: .result,
                    borderHex: "#4F8A63",
                    backgroundHex: "#EEF8F2",
                    titleBackgroundHex: "#DFF0E5",
                    titleTextHex: "#2E6A40",
                    bodyTextHex: "#1F3D2A"
                )
            }
            return styles
        }()
    )

    static func defaultBoxStyles(
        accentHex: String,
        surfaceHex: String,
        borderHex: String,
        secondaryHex: String
    ) -> [TemplateBoxStyle] {
        [
            TemplateBoxStyle(
                variant: .standard,
                borderHex: borderHex,
                backgroundHex: "#FFFFFF",
                titleTextHex: accentHex,
                bodyTextHex: "#22304A"
            ),
            TemplateBoxStyle(
                variant: .summary,
                borderHex: borderHex,
                backgroundHex: surfaceHex,
                titleBackgroundHex: borderHex,
                titleTextHex: accentHex,
                bodyTextHex: "#22304A"
            ),
            TemplateBoxStyle(
                variant: .key,
                borderHex: accentHex,
                backgroundHex: surfaceHex,
                titleBackgroundHex: accentHex,
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#22304A"
            ),
            TemplateBoxStyle(
                variant: .warning,
                borderHex: "#D95C5C",
                backgroundHex: "#FFF4F2",
                titleBackgroundHex: "#F26B6B",
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#4A2A2A"
            ),
            TemplateBoxStyle(
                variant: .exam,
                borderHex: accentHex,
                backgroundHex: "#FFFFFF",
                titleBackgroundHex: "#EEF3FF",
                titleTextHex: accentHex,
                bodyTextHex: "#22304A"
            ),
            TemplateBoxStyle(
                variant: .code,
                borderHex: "#D9DEE8",
                backgroundHex: "#F7F8FB",
                titleBackgroundHex: "#EEF1F6",
                titleTextHex: secondaryHex,
                bodyTextHex: "#1E293B"
            ),
            TemplateBoxStyle(
                variant: .result,
                borderHex: "#3C8C53",
                backgroundHex: "#F4FBF5",
                titleBackgroundHex: "#E3F4E8",
                titleTextHex: "#2E6A40",
                bodyTextHex: "#1F3D2A"
            ),
        ]
    }
}
