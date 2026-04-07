import Foundation
import SQLite3

protocol CuratorRepository: Sendable {
    func save(workspace: Workspace) async throws
    func delete(workspaceID: UUID) async throws
    func save(item: WorkspaceItem) async throws
    func save(version: DraftVersion) async throws
    func save(template: Template) async throws
    func delete(templateID: UUID) async throws
    func save(export: ExportRecord) async throws
    func delete(exportID: UUID) async throws
    func delete(itemID: UUID) async throws
    func save(preferences: AppPreferences) async throws
    func save(lastSession: LastSessionSnapshot) async throws
    func loadSnapshot() async throws -> RepositorySnapshot
}

enum SQLiteRepositoryError: Error {
    case openDatabase(String)
    case prepare(String)
    case execute(String)
    case bind(String)
    case read(String)
}

private struct SQLiteConnectionHandle: @unchecked Sendable {
    let raw: OpaquePointer
}

actor SQLiteCuratorRepository: CuratorRepository {
    private let db: SQLiteConnectionHandle
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(databaseURL: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message: String
            if let handle {
                message = String(cString: sqlite3_errmsg(handle))
            } else {
                message = String(cString: sqlite3_errstr(result))
            }
            throw SQLiteRepositoryError.openDatabase(message)
        }

        db = SQLiteConnectionHandle(raw: handle)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try Self.createSchema(in: db.raw)
    }

    deinit {
        sqlite3_close(db.raw)
    }

    func save(workspace: Workspace) async throws {
        try upsert(record: workspace, table: "workspaces")
    }

    func delete(workspaceID: UUID) async throws {
        let linkedItemIDs = try loadRecords(from: "items", as: WorkspaceItem.self)
            .filter { $0.workspaceId == workspaceID }
            .map(\.id)
        let linkedVersionIDs = try loadRecords(from: "versions", as: DraftVersion.self)
            .filter { linkedItemIDs.contains($0.workspaceItemId) }
            .map(\.id)

        for itemID in linkedItemIDs {
            try deleteRecord(id: itemID, from: "items")
        }
        for versionID in linkedVersionIDs {
            try deleteRecord(id: versionID, from: "versions")
        }

        let exportRecords = try loadRecords(from: "exports", as: ExportRecord.self)
            .filter { linkedVersionIDs.contains($0.draftVersionId) }
        for exportRecord in exportRecords {
            try deleteRecord(id: exportRecord.id, from: "exports")
        }

        try deleteRecord(id: workspaceID, from: "workspaces")
    }

    func save(item: WorkspaceItem) async throws {
        try upsert(record: item, table: "items")
    }

    func save(version: DraftVersion) async throws {
        try upsert(record: version, table: "versions")
    }

    func save(template: Template) async throws {
        try upsert(record: template, table: "templates")
    }

    func delete(templateID: UUID) async throws {
        try deleteRecord(id: templateID, from: "templates")
    }

    func save(export: ExportRecord) async throws {
        try upsert(record: export, table: "exports")
    }

    func delete(exportID: UUID) async throws {
        try deleteRecord(id: exportID, from: "exports")
    }

    func delete(itemID: UUID) async throws {
        let allItems = try loadRecords(from: "items", as: WorkspaceItem.self)
        let item = allItems.first { $0.id == itemID }
        let linkedVersionIDs = try loadRecords(from: "versions", as: DraftVersion.self)
            .filter { $0.workspaceItemId == itemID }
            .map(\.id)
        var exportVersionIDs = Set(linkedVersionIDs)
        if item?.kind == .export, let currentVersionID = item?.currentVersionId {
            exportVersionIDs.insert(currentVersionID)
        }

        let linkedExportItemIDs = allItems
            .filter {
                $0.id != itemID &&
                $0.kind == .export &&
                $0.currentVersionId.map(exportVersionIDs.contains) == true
            }
            .map(\.id)

        for exportItemID in linkedExportItemIDs {
            try deleteRecord(id: exportItemID, from: "items")
        }
        try deleteRecord(id: itemID, from: "items")
        for versionID in linkedVersionIDs {
            try deleteRecord(id: versionID, from: "versions")
        }

        let linkedExportIDs = try loadRecords(from: "exports", as: ExportRecord.self)
            .filter { exportVersionIDs.contains($0.draftVersionId) }
            .map(\.id)
        for exportID in linkedExportIDs {
            try deleteRecord(id: exportID, from: "exports")
        }
    }

    func save(preferences: AppPreferences) async throws {
        try saveSetting(preferences, key: "preferences")
    }

    func save(lastSession: LastSessionSnapshot) async throws {
        try saveSetting(lastSession, key: "last_session")
    }

    private func saveSetting<T: Encodable>(_ value: T, key: String) throws {
        let payload = try encoder.encode(value)
        let sql = "INSERT INTO settings(key, payload) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteRepositoryError.bind(errorMessage)
        }

        try bind(blob: payload, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteRepositoryError.execute(errorMessage)
        }
    }

    func loadSnapshot() async throws -> RepositorySnapshot {
        RepositorySnapshot(
            workspaces: try loadRecords(from: "workspaces", as: Workspace.self).sorted { $0.updatedAt > $1.updatedAt },
            items: try loadRecords(from: "items", as: WorkspaceItem.self).sorted { $0.lastEditedAt > $1.lastEditedAt },
            versions: try loadRecords(from: "versions", as: DraftVersion.self).sorted { $0.createdAt > $1.createdAt },
            templates: try loadRecords(from: "templates", as: Template.self).sorted { $0.name < $1.name },
            exports: try loadRecords(from: "exports", as: ExportRecord.self).sorted { $0.createdAt > $1.createdAt },
            preferences: try loadSetting("preferences", as: AppPreferences.self) ?? .default,
            lastSession: try loadSetting("last_session", as: LastSessionSnapshot.self)
        )
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db.raw, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteRepositoryError.prepare(errorMessage)
        }
        return statement
    }

    private func upsert<T: Encodable & Identifiable>(record: T, table: String) throws where T.ID == UUID {
        let sql = "INSERT INTO \(table)(id, payload) VALUES(?, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        let idString = record.id.uuidString
        guard sqlite3_bind_text(statement, 1, idString, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteRepositoryError.bind(errorMessage)
        }

        try bind(blob: encoder.encode(record), at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteRepositoryError.execute(errorMessage)
        }
    }

    private func deleteRecord(id: UUID, from table: String) throws {
        let statement = try prepare("DELETE FROM \(table) WHERE id = ?;")
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteRepositoryError.bind(errorMessage)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteRepositoryError.execute(errorMessage)
        }
    }

    private func bind(blob: Data, at index: Int32, to statement: OpaquePointer?) throws {
        let result = blob.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(blob.count), SQLITE_TRANSIENT)
        }
        guard result == SQLITE_OK else {
            throw SQLiteRepositoryError.bind(errorMessage)
        }
    }

    private func loadRecords<T: Decodable>(from table: String, as type: T.Type) throws -> [T] {
        let statement = try prepare("SELECT payload FROM \(table);")
        defer { sqlite3_finalize(statement) }

        var records: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let blob = sqlite3_column_blob(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            let data = Data(bytes: blob, count: count)
            records.append(try decoder.decode(T.self, from: data))
        }
        return records
    }

    private func loadSetting<T: Decodable>(_ key: String, as type: T.Type) throws -> T? {
        let statement = try prepare("SELECT payload FROM settings WHERE key = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteRepositoryError.bind(errorMessage)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let blob = sqlite3_column_blob(statement, 0) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, 0))
        let data = Data(bytes: blob, count: count)
        return try decoder.decode(T.self, from: data)
    }

    private var errorMessage: String {
        String(cString: sqlite3_errmsg(db.raw))
    }

    private static func createSchema(in db: OpaquePointer) throws {
        let statements = [
            "CREATE TABLE IF NOT EXISTS workspaces(id TEXT PRIMARY KEY, payload BLOB NOT NULL);",
            "CREATE TABLE IF NOT EXISTS items(id TEXT PRIMARY KEY, payload BLOB NOT NULL);",
            "CREATE TABLE IF NOT EXISTS versions(id TEXT PRIMARY KEY, payload BLOB NOT NULL);",
            "CREATE TABLE IF NOT EXISTS templates(id TEXT PRIMARY KEY, payload BLOB NOT NULL);",
            "CREATE TABLE IF NOT EXISTS exports(id TEXT PRIMARY KEY, payload BLOB NOT NULL);",
            "CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, payload BLOB NOT NULL);",
        ]

        for sql in statements {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw SQLiteRepositoryError.execute(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
