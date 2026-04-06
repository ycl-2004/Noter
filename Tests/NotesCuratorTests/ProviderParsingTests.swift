import Testing
@testable import NotesCurator

struct ProviderParsingTests {
    @Test
    func providerHTTPSessionUsesExtendedTimeoutsForSlowLocalModels() {
        #expect(ProviderHTTP.session.configuration.timeoutIntervalForRequest == 600)
        #expect(ProviderHTTP.session.configuration.timeoutIntervalForResource == 1_800)
    }

    @Test
    func localOllamaDefaultsToIPv4Loopback() {
        let provider = LocalOllamaProvider(modelName: "qwen3:14b")
        #expect(provider.baseURL.absoluteString == "http://127.0.0.1:11434")
    }

    @Test
    func providerResponseParserExtractsJSONAfterThinkingTrace() throws {
        let raw = """
        Thinking...
        <think>
        I should reason through the document before returning the answer.
        </think>
        ```json
        {
          "title": "Merkle Tree Notes",
          "summary": "Merkle Trees support efficient integrity checks.",
          "keyPoints": ["Merkle proofs are logarithmic in proof size."],
          "sections": [
            {
              "title": "Overview",
              "body": "A Merkle Tree hashes leaves and combines them upward."
            }
          ],
          "studyCards": [
            {
              "question": "Why are Merkle Trees useful?",
              "answer": "They let you verify membership without scanning every element."
            }
          ],
          "renderedDocument": "## Merkle Tree Notes\\nUseful for efficient proofs."
        }
        ```
        """

        let parsed = try #require(ProviderResponseParser.parse(raw))
        #expect(parsed.title == "Merkle Tree Notes")
        #expect(parsed.summary == "Merkle Trees support efficient integrity checks.")
        #expect(parsed.studyCards.first?.answer == "They let you verify membership without scanning every element.")
        #expect(parsed.renderedDocument.contains("Thinking...") == false)
    }

    @Test
    func providerResponseParserStripsCodeFencesAndNormalizesActionItems() throws {
        let raw = """
        ```json
        {
          "title": "Q3 Budget Review and Branding Guidelines Update",
          "summary": "The current Q3 budget requires a 15% reduction.",
          "keyPoints": [
            "A 15% reduction in Q3 budget required",
            "Update branding guidelines"
          ],
          "sections": [
            {
              "title": "Budget Review",
              "body": "Reallocate resources."
            }
          ],
          "actionItems": [
            {
              "item": "Conduct budget reallocation meeting",
              "dueDate": "TBD"
            },
            {
              "item": "Update branding guidelines",
              "dueDate": "Within the next 2 weeks"
            }
          ],
          "renderedDocument": "Budget review draft"
        }
        ```
        """

        let parsed = try #require(ProviderResponseParser.parse(raw))
        #expect(parsed.title == "Q3 Budget Review and Branding Guidelines Update")
        #expect(parsed.actionItems == [
            "Conduct budget reallocation meeting",
            "Update branding guidelines",
        ])
        #expect(parsed.renderedDocument == "Budget review draft")
    }

    @Test
    func providerResponseParserSupportsDescriptionStyleActionItems() throws {
        let raw = """
        ```json
        {
          "title": "Q3预算及品牌指南更新",
          "summary": "会议讨论了Q3预算需减少15%。",
          "keyPoints": ["Q3预算减少15%"],
          "sections": [
            {
              "title": "预算讨论",
              "body": "需要重新分配预算。"
            }
          ],
          "actionItems": [
            {
              "description": "对Q3预算进行15%的削减",
              "assignee": "",
              "dueDate": ""
            }
          ],
          "renderedDocument": "中文整理结果"
        }
        ```
        """

        let parsed = try #require(ProviderResponseParser.parse(raw))
        #expect(parsed.actionItems == ["对Q3预算进行15%的削减"])
        #expect(parsed.summary == "会议讨论了Q3预算需减少15%。")
    }

    @Test
    func providerResponseParserSupportsRichLectureNoteFields() throws {
        let raw = """
        {
          "title": "Metaplex Token Metadata Notes",
          "summary": "Explain why metadata exists and how URI points to off-chain JSON.",
          "cueQuestions": [
            "Why is a separate metadata account needed?"
          ],
          "keyPoints": [
            "Mint accounts do not store rich display information"
          ],
          "sections": [
            {
              "title": "Metadata Account",
              "body": "Metaplex separates token logic from display information.",
              "bulletPoints": [
                "Metadata is a PDA",
                "Wallets read name, symbol, and URI"
              ]
            }
          ],
          "glossary": [
            {
              "term": "PDA",
              "definition": "Program Derived Address."
            }
          ],
          "callouts": [
            {
              "kind": "warning",
              "title": "Trust surface",
              "body": "Update authority affects how trustworthy the metadata is."
            }
          ],
          "studyCards": [
            {
              "question": "Why is a separate metadata account needed?",
              "answer": "The mint account does not store rich display fields like name, symbol, and URI."
            }
          ],
          "actionItems": [
            "Compare Metaplex with Token-2022 metadata"
          ],
          "reviewQuestions": [
            "What does URI usually point to?"
          ],
          "renderedDocument": "Rich handout"
        }
        """

        let parsed = try #require(ProviderResponseParser.parse(raw))
        #expect(parsed.cueQuestions == ["Why is a separate metadata account needed?"])
        #expect(parsed.sections.first?.bulletPoints == ["Metadata is a PDA", "Wallets read name, symbol, and URI"])
        #expect(parsed.glossary == [GlossaryItem(term: "PDA", definition: "Program Derived Address.")])
        #expect(parsed.callouts.first?.kind == .warning)
        #expect(parsed.studyCards == [
            StudyCard(
                question: "Why is a separate metadata account needed?",
                answer: "The mint account does not store rich display fields like name, symbol, and URI."
            )
        ])
        #expect(parsed.reviewQuestions == ["What does URI usually point to?"])
    }
}
