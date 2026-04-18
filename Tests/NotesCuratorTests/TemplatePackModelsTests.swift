import Foundation
import Testing
@testable import NotesCurator

struct TemplatePackModelsTests {
    @Test
    func technicalNoteArchetypeExposesExpectedCoreFields() {
        let pack = TemplatePackDefaults.pack(for: .technicalNote, named: "Lecture Notes")

        #expect(pack.behavior.followsVisualTheme)
        #expect(pack.schema.fields.filter { $0.requiredLevel == .coreRequired }.map(\.key).contains("summary_boxes"))
        #expect(pack.layout.blocks.contains(where: { $0.fieldBinding == "example_boxes" }))
        #expect(pack.layout.blocks.contains(where: { $0.blockType == .warningBox }))
        #expect(pack.layout.blocks.first(where: { $0.blockType == .summary })?.styleVariant == TemplateBlockStyleVariant.summary.rawValue)
        #expect(pack.layout.blocks.first(where: { $0.blockType == .keyPoints })?.styleVariant == TemplateBlockStyleVariant.key.rawValue)
    }

    @Test
    func formalDocumentPresetUsesThemeResponsiveMinimalLayout() {
        let pack = TemplatePackDefaults.pack(for: .formalBrief, named: "Formal Document")

        #expect(pack.behavior.followsVisualTheme)
        #expect(pack.layout.blocks.map(\.fieldBinding).contains("meta_boxes"))
        #expect(pack.layout.blocks.map(\.fieldBinding).contains("summary_boxes"))
        #expect(pack.layout.blocks.map(\.fieldBinding).contains("sections"))
        #expect(pack.layout.blocks.map(\.fieldBinding).contains("result_boxes"))
        #expect(pack.layout.blocks.map(\.fieldBinding).contains("question_boxes"))
    }

    @Test
    func summaryAndStudyGuidePresetsExposeDetailedBoxBuckets() {
        let summaryPack = TemplatePackDefaults.pack(for: .technicalNote, named: "Quick Summary")
        let studyPack = TemplatePackDefaults.pack(for: .technicalNote, named: "Study Guide")
        let deepDivePack = TemplatePackDefaults.pack(for: .technicalNote, named: "Technical Deep Dive")

        #expect(summaryPack.layout.blocks.map(\.fieldBinding).contains("code_boxes"))
        #expect(summaryPack.layout.blocks.map(\.fieldBinding).contains("warning_boxes"))
        #expect(studyPack.layout.blocks.map(\.fieldBinding).contains("question_boxes"))
        #expect(studyPack.layout.blocks.map(\.fieldBinding).contains("checklist_boxes"))
        #expect(studyPack.layout.blocks.map(\.fieldBinding).contains("result_boxes"))
        #expect(deepDivePack.layout.blocks.map(\.fieldBinding).contains("explanation_boxes"))
        #expect(deepDivePack.layout.blocks.map(\.fieldBinding).contains("example_boxes"))
        #expect(deepDivePack.layout.blocks.map(\.fieldBinding).contains("code_boxes"))
    }

    @Test
    func legacyMarkdownTemplateMapsIntoTemplatePack() throws {
        let legacy = Template.starterContentTemplate(name: "Study Guide")
        let pack = try legacy.templatePack()

        #expect(pack.identity.name == "Study Guide")
        #expect(pack.schema.fields.contains(where: { $0.key == "summary_boxes" }))
        #expect(pack.layout.blocks.contains(where: { $0.fieldBinding == "question_boxes" }))
    }

    @Test
    func packBackedTemplateCodableRoundTrips() throws {
        let pack = TemplatePack.fixture()
        let template = Template.packBacked(pack, scope: .user)
        let encoded = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(Template.self, from: encoded)

        #expect(try decoded.templatePack().identity.id == pack.identity.id)
    }

    @Test
    func editableCopyPreservesStoredPackData() throws {
        let pack = TemplatePack.fixture(name: "Imported Notes")
        let template = Template.packBacked(pack, scope: .system)

        let editable = template.editableCopy(scope: .user)

        #expect(editable.scope == .user)
        #expect(editable.id != template.id)
        #expect(try editable.templatePack().identity.name == "Imported Notes")
    }

    @Test
    func authoringUpdatePreservesStoredPackData() throws {
        let pack = TemplatePack.fixture(name: "Imported Notes")
        let template = Template.packBacked(pack, scope: .user)

        let updated = template.updatedForAuthoring(
            name: "Imported Notes v2",
            subtitle: "Updated",
            templateDescription: "Still pack-backed",
            body: "",
            config: template.config
        )

        #expect(updated.id == template.id)
        #expect(updated.name == "Imported Notes v2")
        #expect(try updated.templatePack().identity.name == "Imported Notes")
    }

    @Test
    func duplicatedTemplatePreservesStoredPackData() throws {
        let pack = TemplatePack.fixture(name: "Imported Notes")
        let template = Template.packBacked(pack, scope: .user)

        let duplicate = template.duplicated(named: "Imported Notes Copy")

        #expect(duplicate.id != template.id)
        #expect(duplicate.name == "Imported Notes Copy")
        #expect(try duplicate.templatePack().identity.name == "Imported Notes")
    }
}

private extension TemplatePack {
    static func fixture(name: String = "Structured Notes") -> TemplatePack {
        TemplatePack(
            identity: TemplatePackIdentity(
                id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID(),
                name: name,
                description: "Fixture pack"
            ),
            archetype: .technicalNote,
            schema: RecommendedSchema(
                fields: [
                    RecommendedField(
                        key: "overview",
                        label: "Overview",
                        requiredLevel: .coreRequired
                    )
                ]
            ),
            layout: LayoutSpec(
                blocks: [
                    TemplateBlockSpec(
                        id: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
                        blockType: .section,
                        fieldBinding: "overview",
                        styleVariant: "default",
                        emptyBehavior: .placeholder
                    )
                ]
            ),
            style: StyleKit(accentHex: "#2E5AAC"),
            behavior: TemplateBehaviorRules()
        )
    }
}
