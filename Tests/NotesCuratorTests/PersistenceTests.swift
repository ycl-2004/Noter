import Foundation
import Testing
@testable import NotesCurator

struct PersistenceTests {
    @Test
    func sqliteRepositoryPersistsWorkspaceGraphs() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        let repository = try SQLiteCuratorRepository(databaseURL: tempURL)

        let workspace = Workspace(
            name: "Strategy",
            cover: .ocean,
            coverImagePath: "/tmp/strategy-cover.png",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            pinned: true
        )

        let draft = WorkspaceItem(
            workspaceId: workspace.id,
            kind: .draft,
            title: "Quarterly Review",
            summaryPreview: "Summarized quarterly planning notes",
            lastEditedAt: Date(timeIntervalSince1970: 3_000),
            currentVersionId: UUID()
        )

        let version = DraftVersion(
            workspaceItemId: draft.id,
            goalType: .structuredNotes,
            outputLanguage: .english,
            editorDocument: "Edited content",
            structuredDoc: StructuredDocument(
                title: "Quarterly Review",
                summary: "A short summary",
                keyPoints: ["Revenue up", "Risks tracked"],
                sections: [
                    StructuredSection(title: "Overview", body: "Detailed overview")
                ],
                actionItems: ["Share with team"],
                imageSlots: [],
                exportMetadata: ExportMetadata(
                    contentTemplateName: "Structured Notes",
                    visualTemplateName: "Oceanic Blue",
                    preferredFormat: .pdf
                )
            ),
            sourceRefs: [
                SourceReference(kind: .pastedText, title: "Input", excerpt: "Raw text excerpt")
            ],
            imageSuggestions: [],
            createdAt: Date(timeIntervalSince1970: 4_000)
        )

        try await repository.save(workspace: workspace)
        try await repository.save(item: draft)
        try await repository.save(version: version)
        try await repository.save(lastSession: LastSessionSnapshot(sidebarSection: .drafts, workspaceId: workspace.id, itemId: draft.id))

        let snapshot = try await repository.loadSnapshot()

        #expect(snapshot.workspaces == [workspace])
        #expect(snapshot.items == [draft])
        #expect(snapshot.versions == [version])
        #expect(snapshot.lastSession?.itemId == draft.id)
    }

    @Test
    func sqliteRepositorySerializesConcurrentWritesSafely() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        let repository = try SQLiteCuratorRepository(databaseURL: tempURL)
        let workspaceID = UUID()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<25 {
                group.addTask {
                    let item = WorkspaceItem(
                        workspaceId: workspaceID,
                        kind: .draft,
                        title: "Draft \(index)",
                        summaryPreview: "Preview \(index)",
                        lastEditedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                        currentVersionId: nil,
                        status: .processing
                    )
                    try await repository.save(item: item)
                }
            }

            try await group.waitForAll()
        }

        let snapshot = try await repository.loadSnapshot()
        #expect(snapshot.items.count == 25)
    }
}
