import Foundation

enum TemplatePreviewSamples {
    static func document(for key: String, fallbackGoal: GoalType = .structuredNotes) -> StructuredDocument {
        switch key {
        case "action_plan":
            return .actionPlanSample
        case "formal_brief":
            return .formalBriefSample
        case "quick_summary":
            return .quickSummarySample
        case "lecture_notes":
            return .lectureNotesSample
        case "structured_notes":
            return .structuredNotesSample
        case "study_guide":
            return .studyGuideSample
        case "technical_deep_dive":
            return .technicalDeepDiveSample
        default:
            switch fallbackGoal {
            case .actionItems:
                return .actionPlanSample
            case .formalDocument:
                return .formalBriefSample
            case .summary:
                return .quickSummarySample
            case .structuredNotes:
                return .structuredNotesSample
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
        templateBoxes: [
            StructuredTemplateBox(
                kind: .summary,
                title: "Executive Summary",
                body: "Move forward with the staged migration, but gate rollout on observability, support readiness, and customer communication milestones."
            ),
            StructuredTemplateBox(
                kind: .key,
                title: "Key Insight",
                body: "",
                items: [
                    "The staged migration reduces operational risk compared with a single cutover.",
                    "Customer communication has to land before traffic starts moving."
                ]
            ),
            StructuredTemplateBox(
                kind: .meta,
                title: "Document Metadata",
                body: "",
                items: [
                    "Topic: Migration Recommendation",
                    "Source: Internal architecture review",
                    "Audience: Product and operations stakeholders",
                    "Version: v1.2"
                ]
            ),
            StructuredTemplateBox(
                kind: .explanation,
                title: "Scope",
                body: "This version frames the note like a stakeholder-ready brief, so context and trade-offs stay explicit."
            ),
            StructuredTemplateBox(
                kind: .warning,
                title: "Risks and Warnings",
                body: "If telemetry readiness slips, the migration should pause before broad customer rollout."
            ),
            StructuredTemplateBox(
                kind: .code,
                title: "Reference Snippet",
                body: "graph deploy --studio random-winner-game"
            ),
            StructuredTemplateBox(
                kind: .question,
                title: "Questions for Review",
                body: "What condition would force a rollback decision?",
                items: ["Missing telemetry, support readiness, or customer communication sign-off."]
            ),
            StructuredTemplateBox(
                kind: .result,
                title: "Recommendations and Next Steps",
                body: "Proceed with a phased launch and require explicit go/no-go checkpoints."
            )
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
                kind: .summary,
                title: "What This Study Guide Covers",
                body: "This guide organizes the core trade-offs, vocabulary, and recall prompts behind consensus algorithms."
            ),
            StructuredTemplateBox(
                kind: .key,
                title: "Must-Know Concepts",
                body: "",
                items: [
                    "Safety means nodes do not decide conflicting values.",
                    "Liveness means the system continues making progress.",
                    "Network assumptions shape which guarantees are practical."
                ]
            ),
            StructuredTemplateBox(
                kind: .warning,
                title: "Most Common Mistakes",
                body: "Do not treat safety and liveness as interchangeable. A system can preserve one while temporarily sacrificing the other."
            ),
            StructuredTemplateBox(
                kind: .code,
                title: "Formula Set",
                body: "propose value -> collect votes -> reach quorum -> commit decision"
            ),
            StructuredTemplateBox(
                kind: .question,
                title: "Short Answer Practice",
                body: "What failure mode makes liveness hardest to preserve?",
                items: ["Highly asynchronous networks with long delays"]
            ),
            StructuredTemplateBox(
                kind: .checklist,
                title: "Revision Checklist",
                body: "",
                items: [
                    "Explain safety without mentioning liveness.",
                    "Explain liveness without assuming synchrony.",
                    "Compare quorum design with fault tolerance."
                ]
            ),
            StructuredTemplateBox(
                kind: .result,
                title: "Before the Exam",
                body: "Be ready to explain why safety can be preserved even when liveness temporarily stalls."
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

    static let quickSummarySample = StructuredDocument.fixture(
        title: "Merkle Trees Quick Summary",
        summary: "Merkle trees compress many data items into one root so proofs stay small and verification stays fast.",
        keyPoints: [
            "A Merkle root represents the whole dataset.",
            "Proof size grows logarithmically with the number of leaves."
        ],
        sections: [
            StructuredSection(
                title: "Compressed Explanation",
                body: "Hash each leaf, combine neighbors upward, and compare the final root with the trusted root."
            )
        ],
        templateBoxes: [
            StructuredTemplateBox(
                kind: .summary,
                title: "One-Sentence Summary",
                body: "Merkle trees compress many data items into one root so proofs stay small and verification stays fast."
            ),
            StructuredTemplateBox(
                kind: .key,
                title: "Most Important Ideas",
                body: "",
                items: [
                    "A Merkle root represents the whole dataset.",
                    "Proof size grows logarithmically with the number of leaves."
                ]
            ),
            StructuredTemplateBox(
                kind: .code,
                title: "Formula Snapshot",
                body: "leaf hash -> parent hash -> root hash"
            ),
            StructuredTemplateBox(
                kind: .warning,
                title: "Mistakes to Avoid",
                body: "Do not confuse a Merkle proof with the underlying data itself."
            ),
            StructuredTemplateBox(
                kind: .result,
                title: "Final Takeaway",
                body: "Use Merkle trees when you need tamper-evident inclusion proofs without shipping the full dataset."
            )
        ]
    )

    static let lectureNotesSample = StructuredDocument.fixture(
        title: "The Graph Lecture Notes",
        summary: "This lesson explains how a subgraph maps blockchain events into queryable entities.",
        keyPoints: [
            "Mappings translate chain activity into entities.",
            "The schema decides what the frontend can query later."
        ],
        sections: [
            StructuredSection(
                title: "Lecture Flow",
                body: "Start from the chain event, define the schema, write mappings, deploy, then test the query path."
            )
        ],
        templateBoxes: [
            StructuredTemplateBox(
                kind: .summary,
                title: "Lecture Overview",
                body: "This lesson explains how a subgraph maps blockchain events into queryable entities."
            ),
            StructuredTemplateBox(
                kind: .key,
                title: "Core Idea",
                body: "",
                items: [
                    "Mappings translate chain activity into entities.",
                    "The schema decides what the frontend can query later."
                ]
            ),
            StructuredTemplateBox(
                kind: .explanation,
                title: "Definition",
                body: "A subgraph is an indexing recipe that tells Graph Node which events to watch and how to store them."
            ),
            StructuredTemplateBox(
                kind: .example,
                title: "Example",
                body: "When a lottery contract emits WinnerPicked, the mapping writes the winner address into the indexed entity."
            ),
            StructuredTemplateBox(
                kind: .warning,
                title: "Common Mistake",
                body: "If the ABI or event signature is wrong, the mapping will never receive the event."
            ),
            StructuredTemplateBox(
                kind: .exam,
                title: "Exam Tip",
                body: "Explain the full data flow from emitted event to frontend query result."
            ),
            StructuredTemplateBox(
                kind: .checklist,
                title: "Review Checklist",
                body: "",
                items: [
                    "Can you name the three core files in a subgraph project?",
                    "Can you explain what the schema controls?",
                    "Can you tell whether indexing succeeded?"
                ]
            ),
            StructuredTemplateBox(
                kind: .result,
                title: "Quick Recap",
                body: "A successful subgraph gives the frontend stable queryable entities built from contract events."
            )
        ]
    )

    static let structuredNotesSample = StructuredDocument.fixture(
        title: "Structured Notes Example",
        summary: "These notes reorganize a messy source into a clean structure with stable section boundaries.",
        keyPoints: [
            "Each section should stand on its own.",
            "Support boxes should clarify, not duplicate the body."
        ],
        sections: [
            StructuredSection(
                title: "Main Section",
                body: "The cleaned version groups related ideas together instead of preserving the original noisy order.",
                bulletPoints: [
                    "Use one main idea per section.",
                    "Keep the takeaway obvious."
                ]
            )
        ],
        templateBoxes: [
            StructuredTemplateBox(
                kind: .summary,
                title: "Document Scope",
                body: "These notes reorganize a messy source into a clean structure with stable section boundaries."
            ),
            StructuredTemplateBox(
                kind: .key,
                title: "Key Insight",
                body: "",
                items: [
                    "Each section should stand on its own.",
                    "Support boxes should clarify, not duplicate the body."
                ]
            ),
            StructuredTemplateBox(
                kind: .explanation,
                title: "Important Note",
                body: "This format favors clarity and long-term rereadability over strict lecture chronology."
            ),
            StructuredTemplateBox(
                kind: .example,
                title: "Application",
                body: "Turn a rough transcript into sections like concept, mechanism, example, and conclusion."
            ),
            StructuredTemplateBox(
                kind: .warning,
                title: "Clarification",
                body: "Do not split sections so aggressively that every paragraph becomes its own heading."
            ),
            StructuredTemplateBox(
                kind: .result,
                title: "Section Summary",
                body: "A balanced note should be easy to scan, teach from, and export without reformatting."
            )
        ]
    )

    static let technicalDeepDiveSample = StructuredDocument.fixture(
        title: "Technical Deep Dive: Event Indexing Pipeline",
        summary: "This walkthrough explains how events move from chain logs through mappings into indexed query results.",
        keyPoints: [
            "The indexing pipeline is deterministic.",
            "Most failures happen at the boundaries between config, ABI, and handler logic."
        ],
        sections: [
            StructuredSection(
                title: "Deep Dive",
                body: "The system listens for matching logs, decodes event payloads, runs deterministic handlers, and persists the resulting entities."
            )
        ],
        templateBoxes: [
            StructuredTemplateBox(
                kind: .summary,
                title: "Primary Goal",
                body: "This walkthrough explains how events move from chain logs through mappings into indexed query results."
            ),
            StructuredTemplateBox(
                kind: .key,
                title: "One-Sentence Core Insight",
                body: "",
                items: [
                    "The indexing pipeline is deterministic.",
                    "Most failures happen at the boundaries between config, ABI, and handler logic."
                ]
            ),
            StructuredTemplateBox(
                kind: .explanation,
                title: "System Box",
                body: "Think of the indexer as a compiler pass over blockchain history that keeps producing database rows."
            ),
            StructuredTemplateBox(
                kind: .code,
                title: "Implementation Outline",
                body: "match log -> decode ABI -> run handler -> upsert entity -> serve GraphQL query"
            ),
            StructuredTemplateBox(
                kind: .warning,
                title: "Things That Commonly Go Wrong",
                body: "Handler code may compile even when the manifest points at the wrong event signature."
            ),
            StructuredTemplateBox(
                kind: .example,
                title: "Edge Cases to Consider",
                body: "Reorgs, duplicate entity IDs, and nullable fields that the frontend incorrectly treats as required."
            ),
            StructuredTemplateBox(
                kind: .result,
                title: "Ultimate Summary",
                body: "Reliable indexing depends on aligning manifest config, ABI definitions, and deterministic handler behavior."
            )
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
