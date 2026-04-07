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

    @Test
    func sqliteRepositoryDeletesWorkspaceItemsAndDerivedExportsTogether() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        let repository = try SQLiteCuratorRepository(databaseURL: tempURL)

        let workspace = Workspace(name: "Cleanup", cover: .ocean)
        let draft = WorkspaceItem(
            workspaceId: workspace.id,
            kind: .draft,
            title: "Delete me",
            summaryPreview: "Completed note",
            currentVersionId: UUID()
        )
        let version = DraftVersion(
            id: draft.currentVersionId ?? UUID(),
            workspaceItemId: draft.id,
            goalType: .structuredNotes,
            outputLanguage: .english,
            editorDocument: "Delete me",
            structuredDoc: StructuredDocument(
                title: "Delete me",
                summary: "Completed note",
                keyPoints: [],
                sections: [],
                actionItems: [],
                imageSlots: [],
                exportMetadata: ExportMetadata(
                    contentTemplateName: "Structured Notes",
                    visualTemplateName: "Oceanic Blue",
                    preferredFormat: .txt
                )
            ),
            sourceRefs: [],
            imageSuggestions: []
        )
        let exportRecord = ExportRecord(
            draftVersionId: version.id,
            format: .txt,
            outputPath: "/tmp/delete-me.txt"
        )
        let exportItem = WorkspaceItem(
            workspaceId: workspace.id,
            kind: .export,
            title: "delete-me.txt",
            summaryPreview: "Exported TXT file",
            currentVersionId: version.id
        )

        try await repository.save(workspace: workspace)
        try await repository.save(item: draft)
        try await repository.save(version: version)
        try await repository.save(export: exportRecord)
        try await repository.save(item: exportItem)

        try await repository.delete(itemID: draft.id)

        let snapshot = try await repository.loadSnapshot()
        #expect(snapshot.items.isEmpty)
        #expect(snapshot.versions.isEmpty)
        #expect(snapshot.exports.isEmpty)
    }

    @Test
    func sqliteRepositoryDeletesExportRecordsWithoutTouchingItemsOrVersions() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        let repository = try SQLiteCuratorRepository(databaseURL: tempURL)

        let workspace = Workspace(name: "Exports", cover: .ocean)
        let draft = WorkspaceItem(
            workspaceId: workspace.id,
            kind: .draft,
            title: "Keep me",
            summaryPreview: "Original note",
            currentVersionId: UUID()
        )
        let version = DraftVersion(
            id: draft.currentVersionId ?? UUID(),
            workspaceItemId: draft.id,
            goalType: .structuredNotes,
            outputLanguage: .english,
            editorDocument: "Keep me",
            structuredDoc: StructuredDocument(
                title: "Keep me",
                summary: "Original note",
                keyPoints: [],
                sections: [],
                actionItems: [],
                imageSlots: [],
                exportMetadata: ExportMetadata(
                    contentTemplateName: "Structured Notes",
                    visualTemplateName: "Oceanic Blue",
                    preferredFormat: .pdf
                )
            ),
            sourceRefs: [],
            imageSuggestions: []
        )
        let exportRecord = ExportRecord(
            draftVersionId: version.id,
            format: .pdf,
            outputPath: "/tmp/keep-me.pdf"
        )
        let exportItem = WorkspaceItem(
            workspaceId: workspace.id,
            kind: .export,
            title: "keep-me.pdf",
            summaryPreview: "Exported PDF file",
            currentVersionId: version.id
        )

        try await repository.save(workspace: workspace)
        try await repository.save(item: draft)
        try await repository.save(version: version)
        try await repository.save(export: exportRecord)
        try await repository.save(item: exportItem)

        try await repository.delete(exportID: exportRecord.id)

        let snapshot = try await repository.loadSnapshot()
        #expect(snapshot.exports.isEmpty)
        #expect(snapshot.items.count == 2)
        #expect(snapshot.versions.count == 1)
        #expect(snapshot.versions.first?.id == version.id)
    }
}
