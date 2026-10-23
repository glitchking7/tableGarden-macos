import Foundation
import CSQLite

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Confined to its caller's serial executor. User databases are opened read-only in this milestone.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?
    public init(path: String) throws {
        guard !path.utf8.contains(0) else { throw SQLiteFailure("O caminho contém um caractere inválido.") }
        let code = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK else { let error = failure(); sqlite3_close(handle); handle = nil; throw error }
        guard sqlite3_exec(handle, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF;", nil, nil, nil) == SQLITE_OK else { let error = failure(); sqlite3_close(handle); handle = nil; throw error }
        sqlite3_set_authorizer(handle, { _, action, first, second, _, _ in
            // Never let a query create/attach another file or load native extensions.
            if action == SQLITE_ATTACH || action == SQLITE_DETACH || action == SQLITE_TRANSACTION || action == SQLITE_SAVEPOINT { return SQLITE_DENY }
            if action == SQLITE_FUNCTION, let second, String(cString: second).lowercased() == "load_extension" { return SQLITE_DENY }
            if action == SQLITE_PRAGMA {
                let name = first.map { String(cString: $0).lowercased() } ?? ""
                let withArgument: Set<String> = ["table_info", "table_xinfo", "index_list", "index_info", "index_xinfo", "foreign_key_list", "table_list", "integrity_check", "quick_check", "foreign_key_check"]
                let withoutArgument: Set<String> = ["database_list", "compile_options", "user_version", "schema_version", "encoding", "page_count", "freelist_count"]
                return withArgument.contains(name) || (withoutArgument.contains(name) && second == nil) ? SQLITE_OK : SQLITE_DENY
            }
            return SQLITE_OK
        }, nil)
    }
    deinit { sqlite3_close(handle) }
    private func failure() -> SQLiteFailure { SQLiteFailure(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Não foi possível abrir o banco SQLite.") }

    public func execute(_ sql: String, parameters: [SQLValue] = [], limit: Int = 1000, cancellation: QueryCancellation = QueryCancellation()) throws -> [QueryResult] {
        guard !sql.utf8.contains(0) else { throw SQLiteFailure("O SQL contém um caractere nulo inválido.") }
        guard sql.utf8.count <= 1_000_000 else { throw SQLiteFailure("A consulta excede o limite de 1 MB.") }
        guard !cancellation.shouldStop else { throw SQLiteFailure("Operação cancelada ou tempo limite atingido.") }
        let context = Unmanaged.passUnretained(cancellation).toOpaque()
        sqlite3_progress_handler(handle, 1000, { context in
            guard let context else { return 0 }
            return Unmanaged<QueryCancellation>.fromOpaque(context).takeUnretainedValue().shouldStop ? 1 : 0
        }, context)
        sqlite3_busy_handler(handle, { context, count in
            guard let context, count < 100 else { return 0 }
            let flag = Unmanaged<QueryCancellation>.fromOpaque(context).takeUnretainedValue()
            if flag.shouldStop { return 0 }
            Thread.sleep(forTimeInterval: 0.01)
            return 1
        }, context)
        defer { sqlite3_progress_handler(handle, 0, nil, nil); sqlite3_busy_handler(handle, nil, nil) }
        var results: [QueryResult] = []
        var bytes = 0
        try sql.withCString { start in
            var cursor: UnsafePointer<CChar>? = start
            while let current = cursor, current.pointee != 0 {
                if cancellation.shouldStop { throw SQLiteFailure("Operação cancelada ou tempo limite atingido.") }
                var stmt: OpaquePointer?
                var tail: UnsafePointer<CChar>?
                let code = sqlite3_prepare_v2(handle, current, -1, &stmt, &tail)
                guard code == SQLITE_OK else { throw failure() }
                cursor = tail
                guard let stmt else { continue }
                defer { sqlite3_finalize(stmt) }
                guard results.count < 10 else { throw SQLiteFailure("Execute no máximo 10 comandos por vez.") }
                guard sqlite3_stmt_readonly(stmt) != 0 else { throw SQLiteFailure("Este banco está aberto somente para leitura. Alterações serão habilitadas em uma próxima etapa.") }
                let count = Int(sqlite3_bind_parameter_count(stmt))
                guard count == parameters.count else { throw SQLiteFailure("A consulta espera \(count) parâmetros; foram informados \(parameters.count).") }
                for (index, value) in parameters.enumerated() { try bind(value, to: stmt, index: Int32(index + 1)) }
                let columns = (0..<sqlite3_column_count(stmt)).map { String(cString: sqlite3_column_name(stmt, $0)) }
                var rows: [[SQLValue]] = []
                let started = Date()
                var truncated = false
                while true {
                    if cancellation.shouldStop { throw SQLiteFailure("Operação cancelada ou tempo limite atingido.") }
                    let step = sqlite3_step(stmt)
                    if step == SQLITE_DONE { break }
                    guard step == SQLITE_ROW else {
                        if step == SQLITE_INTERRUPT { throw SQLiteFailure("Operação cancelada ou tempo limite atingido.") }
                        throw failure()
                    }
                    if rows.count >= max(1, limit) { truncated = true; break }
                    var row: [SQLValue] = []
                    for index in 0..<sqlite3_column_count(stmt) {
                        let valueType = sqlite3_column_type(stmt, index)
                        let size = Int(sqlite3_column_bytes(stmt, index))
                        bytes += max(size, 8)
                        guard size <= 1_048_576, bytes <= 16_777_216 else { throw SQLiteFailure("O resultado excede 16 MB ou contém uma célula maior que 1 MB. Restrinja as colunas ou filtre a consulta.") }
                        switch valueType {
                        case SQLITE_NULL: row.append(.null)
                        case SQLITE_INTEGER: row.append(.integer(sqlite3_column_int64(stmt, index)))
                        case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(stmt, index)))
                        case SQLITE_BLOB:
                            row.append(.blob(sqlite3_column_blob(stmt, index).map { Data(bytes: $0, count: size) } ?? Data()))
                        default:
                            let pointer = sqlite3_column_text(stmt, index)
                            let data = pointer.map { Data(bytes: $0, count: size) } ?? Data()
                            row.append(.text(String(decoding: data, as: UTF8.self)))
                        }
                    }
                    rows.append(row)
                }
                let statementSQL = sqlite3_sql(stmt).map { String(cString: $0) } ?? sql
                results.append(QueryResult(sql: statementSQL, columns: columns, rows: rows, truncated: truncated, duration: Date().timeIntervalSince(started)))
            }
        }
        return results
    }
    private func bind(_ value: SQLValue, to stmt: OpaquePointer, index: Int32) throws {
        let result: Int32
        switch value {
        case .null: result = sqlite3_bind_null(stmt, index)
        case .integer(let n): result = sqlite3_bind_int64(stmt, index, n)
        case .real(let n): result = sqlite3_bind_double(stmt, index, n)
        case .text(let s): result = s.withCString { sqlite3_bind_text(stmt, index, $0, Int32(s.utf8.count), transient) }
        case .blob(let data): result = data.isEmpty ? sqlite3_bind_zeroblob(stmt, index, 0) : data.withUnsafeBytes { sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32(data.count), transient) }
        }
        guard result == SQLITE_OK else { throw failure() }
    }
    public func objects(cancellation: QueryCancellation = QueryCancellation()) throws -> [DatabaseObject] {
        let rows = try execute("SELECT name, type, coalesce(sql, '') FROM sqlite_schema WHERE type IN ('table','view') AND name NOT GLOB 'sqlite_*' ORDER BY name", limit: 5000, cancellation: cancellation).first!
        guard !rows.truncated else { throw SQLiteFailure("Este banco excede o limite inicial de 5.000 tabelas e views.") }
        return rows.rows.map { DatabaseObject(name: $0[0].display, kind: $0[1].display, ddl: $0[2].display) }
    }
    public func page(object: String, offset: Int, size: Int = 200, cancellation: QueryCancellation = QueryCancellation()) throws -> TablePage {
        let info = try execute("SELECT name, type, \"notnull\", dflt_value, pk FROM pragma_table_xinfo(?)", parameters: [.text(object)], limit: 2000, cancellation: cancellation).first!
        let columns = info.rows.map { ColumnInfo(name: $0[0].display, type: $0[1].display, notNull: $0[2] == .integer(1), defaultValue: $0[3] == .null ? nil : $0[3].display, primaryKeyPosition: Int($0[4].display) ?? 0) }
        let keys = columns.filter { $0.primaryKeyPosition > 0 }.sorted { $0.primaryKeyPosition < $1.primaryKeyPosition }
        let order = keys.isEmpty ? "" : " ORDER BY " + keys.map { quotedIdentifier($0.name) }.joined(separator: ", ")
        let pageSize = max(1, min(size, 1000))
        let sql = "SELECT * FROM \(quotedIdentifier(object))\(order) LIMIT \(pageSize + 1) OFFSET \(max(0, offset))"
        let loaded = try execute(sql, limit: pageSize + 1, cancellation: cancellation).first!
        let hasNext = loaded.rows.count > pageSize
        let result = QueryResult(sql: sql, columns: loaded.columns, rows: Array(loaded.rows.prefix(pageSize)), truncated: false, duration: loaded.duration)
        let indexes = try execute("SELECT name FROM pragma_index_list(?)", parameters: [.text(object)], cancellation: cancellation).first!.rows.map { $0[0].display }
        return TablePage(columns: columns, result: result, indexes: indexes, hasNext: hasNext)
    }
    public func foreignKeys(cancellation: QueryCancellation = QueryCancellation()) throws -> [ForeignKey] {
        let result = try execute("SELECT m.name, f.\"from\", f.\"table\", coalesce(f.\"to\", '(chave primária)') FROM sqlite_schema m JOIN pragma_foreign_key_list(m.name) f WHERE m.type = 'table' ORDER BY m.name, f.id, f.seq", limit: 5000, cancellation: cancellation).first!
        guard !result.truncated else { throw SQLiteFailure("O banco excede 5.000 vínculos nesta versão.") }
        return result.rows.map { ForeignKey(sourceTable: $0[0].display, sourceColumn: $0[1].display, targetTable: $0[2].display, targetColumn: $0[3].display) }
    }
}

public actor DatabaseService {
    private var database: SQLiteDatabase?
    public init() {}
    public func connect(path: String, cancellation: QueryCancellation) throws -> [DatabaseObject] {
        let candidate = try SQLiteDatabase(path: path)
        let objects = try candidate.objects(cancellation: cancellation)
        database = candidate
        return objects
    }
    public func page(object: String, offset: Int, cancellation: QueryCancellation) throws -> TablePage {
        guard let database else { throw SQLiteFailure("Abra um banco SQLite primeiro.") }
        return try database.page(object: object, offset: offset, cancellation: cancellation)
    }
    public func execute(sql: String, parameters: [SQLValue], cancellation: QueryCancellation) throws -> [QueryResult] {
        guard let database else { throw SQLiteFailure("Abra um banco SQLite primeiro.") }
        return try database.execute(sql, parameters: parameters, cancellation: cancellation)
    }
    public func foreignKeys(cancellation: QueryCancellation) throws -> [ForeignKey] {
        guard let database else { throw SQLiteFailure("Abra um banco SQLite primeiro.") }
        return try database.foreignKeys(cancellation: cancellation)
    }
}
