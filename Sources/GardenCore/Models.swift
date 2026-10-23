import Foundation

public enum SQLValue: Codable, Equatable, Sendable {
    case null, integer(Int64), real(Double), text(String), blob(Data)
    public var display: String {
        switch self {
        case .null: return "NULL"
        case .integer(let n): return String(n)
        case .real(let n): return String(n)
        case .text(let s): return s
        case .blob(let data): return "BLOB · \(data.count) bytes · " + data.prefix(16).map { String(format: "%02X", $0) }.joined()
        }
    }
}
public struct QueryResult: Identifiable, Sendable {
    public let id = UUID()
    public let sql: String
    public let columns: [String]
    public let rows: [[SQLValue]]
    public let truncated: Bool
    public let duration: TimeInterval
}
public struct DatabaseObject: Identifiable, Sendable {
    public let name: String
    public let kind: String
    public let ddl: String
    public var id: String { name }
}
public struct ColumnInfo: Identifiable, Sendable {
    public let name: String
    public let type: String
    public let notNull: Bool
    public let defaultValue: String?
    public let primaryKeyPosition: Int
    public var id: String { name }
}
public struct ForeignKey: Identifiable, Sendable {
    public let sourceTable: String
    public let sourceColumn: String
    public let targetTable: String
    public let targetColumn: String
    public var id: String { "\(sourceTable).\(sourceColumn)→\(targetTable).\(targetColumn)" }
}
public struct TablePage: Sendable {
    public let columns: [ColumnInfo]
    public let result: QueryResult
    public let indexes: [String]
    public let hasNext: Bool
}
public struct SavedQuery: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var sql: String
    public init(name: String, sql: String) { self.name = name; self.sql = sql }
}
public struct QueryRun: Identifiable, Codable, Sendable {
    public var id = UUID()
    public let sql: String
    public let date: Date
    public let database: String
    public let status: String
    public let rowCount: Int
    public let duration: TimeInterval
    public let error: String?
    public init(sql: String, database: String, status: String, rowCount: Int, duration: TimeInterval, error: String? = nil) {
        self.sql = sql; self.date = Date(); self.database = database; self.status = status
        self.rowCount = rowCount; self.duration = duration; self.error = error
    }
}
public struct LocalState: Codable, Sendable {
    public var version = 1
    public var saved: [SavedQuery] = []
    public var history: [QueryRun] = []
    public var recentPaths: [String] = []
    public var draft = "SELECT sqlite_version() AS versao;"
    public init() {}
}
public struct SQLiteFailure: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

/// A flag shared with SQLite's progress/busy callbacks. Cancelling never waits on the database actor.
public final class QueryCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let deadline: Date
    public init(timeout: TimeInterval = 60) { deadline = Date().addingTimeInterval(timeout) }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var shouldStop: Bool { lock.lock(); defer { lock.unlock() }; return cancelled || Date() >= deadline }
}
public func quotedIdentifier(_ name: String) -> String { "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
