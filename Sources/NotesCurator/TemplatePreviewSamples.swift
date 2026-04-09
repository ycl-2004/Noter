import Foundation

enum TemplatePreviewSamples {
    static func document(for key: String, fallbackGoal: GoalType = .structuredNotes) -> StructuredDocument {
        switch key {
        case "action_plan":
            return .actionPlanSample
        case "formal_brief":
            return .formalBriefSample
        case "study_guide":
            return .studyGuideSample
        default:
            switch fallbackGoal {
            case .actionItems:
                return .actionPlanSample
            case .formalDocument:
                return .formalBriefSample
            case .summary, .structuredNotes:
                return .studyGuideSample
            }
        }
    }
}

extension StructuredDocument {
    static func fixture(
        title: String = "Fixture Draft",
        summary: String = "Fixture summary",
        cueQuestions: [String] = [],
        keyPoints: [String] = [],
        sections: [StructuredSection] = [],
        glossary: [GlossaryItem] = [],
        callouts: [StructuredCallout] = [],
        templateBoxes: [StructuredTemplateBox] = [],
        warnings: [String] = [],
        studyCards: [StudyCard] = [],
        actionItems: [String] = [],
        reviewQuestions: [String] = [],
        imageSlots: [ImageSlot] = [],
        exportMetadata: ExportMetadata = ExportMetadata(
            contentTemplateName: "Structured Notes",
            visualTemplateName: "Oceanic Blue",
            preferredFormat: .markdown
        )
    ) -> StructuredDocument {
        StructuredDocument(
            title: title,
            summary: summary,
            cueQuestions: cueQuestions,
            keyPoints: keyPoints,
            sections: sections,
            glossary: glossary,
            callouts: callouts + warnings.map {
                StructuredCallout(kind: .warning, title: "Warning", body: $0)
            },
            templateBoxes: templateBoxes,
            studyCards: studyCards,
            actionItems: actionItems,
            reviewQuestions: reviewQuestions,
            imageSlots: imageSlots,
            exportMetadata: exportMetadata
        )
    }

    static let actionPlanSample = StructuredDocument.fixture(
        title: "Launch Action Plan",
        summary: "Finalize the launch plan, confirm ownership, and keep execution blockers visible.",
        keyPoints: [
            "The launch date is fixed, so dependencies need tighter coordination.",
            "Legal review and customer messaging are the highest-risk blockers."
        ],
        sections: [
            StructuredSection(
                title: "Current Status",
                body: "Design is approved, the landing page copy is in legal review, and the onboarding checklist still needs product sign-off.",
                bulletPoints: [
                    "Engineering cut-off is Thursday afternoon.",
                    "The CRM campaign draft is ready once messaging is approved."
                ]
            ),
            StructuredSection(
                title: "Risks",
                body: "Cross-team dependencies are the main source of delay risk because several approvals still sit with shared stakeholders.",
                bulletPoints: [
                    "Legal review may slip into next week.",
                    "Support documentation is still missing screenshots."
                ]
            )
        ],
        actionItems: [
            "Assign owners to the remaining launch checklist items.",
            "Track deadlines for legal review and support documentation.",
            "Schedule a daily 15-minute unblocker check-in until launch."
        ],
        reviewQuestions: [
            "Which approvals still block the launch?",
            "What should happen first if the legal review slips?"
        ]
    )

    static let formalBriefSample = StructuredDocument.fixture(
        title: "Migration Recommendation Brief",
        summary: "Move forward with the staged migration, but gate rollout on observability, support readiness, and customer communication milestones.",
        keyPoints: [
            "The staged migration reduces operational risk compared with a single cutover.",
            "Customer communication has to land before traffic starts moving."
        ],
        sections: [
            StructuredSection(
                title: "Situation",
                body: "The legacy stack is constraining release velocity and creates avoidable incident response overhead during peak hours."
            ),
            StructuredSection(
                title: "Assessment",
                body: "A phased migration gives the team time to validate telemetry, prove support playbooks, and lower blast radius before broad rollout."
            ),
            StructuredSection(
                title: "Decision Considerations",
                body: "The trade-off is a slightly longer migration window in exchange for clearer accountability and fewer customer surprises."
            )
        ],
        glossary: [
            GlossaryItem(term: "Cutover", definition: "The point where production traffic moves from the old system to the new system."),
            GlossaryItem(term: "Blast Radius", definition: "The scope of users or systems affected if a migration step fails.")
        ],
        actionItems: [
            "Approve the phased migration plan.",
            "Publish the customer communication timeline.",
            "Define rollback ownership for each migration stage."
        ]
    )

    static let studyGuideSample = StructuredDocument.fixture(
        title: "Consensus Algorithms Study Guide",
        summary: "This guide organizes the core trade-offs, vocabulary, and recall prompts behind consensus algorithms.",
        cueQuestions: [
            "Why does consensus become harder when the network is unreliable?",
            "How do safety and liveness pull against each other?"
        ],
        keyPoints: [
            "Safety means nodes do not decide conflicting values.",
            "Liveness means the system continues making progress.",
            "Network assumptions shape which guarantees are practical."
        ],
        sections: [
            StructuredSection(
                title: "Core Concept",
                body: "Consensus algorithms coordinate distributed nodes so they can agree on a shared result despite failures and delay."
            ),
            StructuredSection(
                title: "Trade-offs",
                body: "Stronger fault tolerance or simpler reasoning usually comes with higher communication cost or stricter timing assumptions."
            )
        ],
        glossary: [
            GlossaryItem(term: "Safety", definition: "A guarantee that the system avoids contradictory decisions."),
            GlossaryItem(term: "Liveness", definition: "A guarantee that the system can continue toward a decision."),
            GlossaryItem(term: "Quorum", definition: "The minimum subset of nodes needed to make a valid decision.")
        ],
        templateBoxes: [
            StructuredTemplateBox(
                kind: .key,
                title: "Core Lens",
                body: "Safety and liveness are the two guarantees every consensus discussion keeps balancing."
            ),
            StructuredTemplateBox(
                kind: .warning,
                title: "Common Trap",
                body: "Do not treat safety and liveness as interchangeable. A system can preserve one while temporarily sacrificing the other."
            ),
            StructuredTemplateBox(
                kind: .code,
                title: "Pseudo Flow",
                body: "propose value -> collect votes -> reach quorum -> commit decision"
            ),
            StructuredTemplateBox(
                kind: .exam,
                title: "Self-Check",
                body: "What failure mode makes liveness hardest to preserve?",
                items: ["Highly asynchronous networks with long delays"]
            )
        ],
        studyCards: [
            StudyCard(question: "What is the difference between safety and liveness?", answer: "Safety prevents conflicting results; liveness keeps the system moving toward completion."),
            StudyCard(question: "What role does a quorum play?", answer: "It defines the threshold of participation needed for a decision to count.")
        ],
        reviewQuestions: [
            "What happens to liveness when the network becomes highly asynchronous?",
            "Why can quorum design affect fault tolerance?"
        ]
    )
}

extension DraftVersion {
    static func previewDraft(
        document: StructuredDocument,
        goalType: GoalType,
        outputLanguage: OutputLanguage = .english,
        editorDocument: String
    ) -> DraftVersion {
        DraftVersion(
            workspaceItemId: UUID(),
            goalType: goalType,
            outputLanguage: outputLanguage,
            editorDocument: editorDocument,
            structuredDoc: document,
            sourceRefs: [],
            imageSuggestions: []
        )
    }
}
