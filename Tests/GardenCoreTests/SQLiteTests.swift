import XCTest
import CSQLite
@testable import GardenCore

final class SQLiteTests: XCTestCase {
    private var directory: URL!
    private var path: String { directory.appendingPathComponent("fixture.sqlite").path }
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write("""
        CREATE TABLE usuarios(id INTEGER PRIMARY KEY, nome TEXT NOT NULL, cidade TEXT);
        INSERT INTO usuarios VALUES(1,'Ana','São Paulo'),(2,'Bruno','Curitiba');
        CREATE TABLE pedidos(id INTEGER PRIMARY KEY, usuario_id INTEGER REFERENCES usuarios(id));
        CREATE INDEX pedido_usuario ON pedidos(usuario_id);
        CREATE VIEW nomes AS SELECT nome FROM usuarios;
        CREATE TABLE "a""b"("strange column" TEXT);
        INSERT INTO "a""b" VALUES('valor');
        """)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func write(_ sql: String) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw SQLiteFailure(String(cString: sqlite3_errmsg(handle))) }
    }
    func testReadsActualObjectsColumnsViewsAndForeignKeys() throws {
        let db = try SQLiteDatabase(path: path)
        let objects = try db.objects()
        XCTAssertEqual(Set(objects.map(\.name)), ["usuarios", "pedidos", "nomes", "a\"b"])
        XCTAssertEqual(objects.first { $0.name == "nomes" }?.kind, "view")
        let page = try db.page(object: "pedidos", offset: 0)
        XCTAssertEqual(page.columns.first?.primaryKeyPosition, 1)
        XCTAssertEqual(page.indexes, ["pedido_usuario"])
        let keys = try db.foreignKeys()
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].sourceColumn, "usuario_id")
        XCTAssertEqual(keys[0].targetTable, "usuarios")
        XCTAssertEqual(try db.page(object: "a\"b", offset: 0).result.rows, [[.text("valor")]])
    }
    func testTypedValuesUnicodeNullAndBinary() throws {
        let db = try SQLiteDatabase(path: path)
        let result = try XCTUnwrap(db.execute("SELECT 9223372036854775807, 1.25, NULL, 'Olá 🌱', x'00FF', x'', ''").first)
        XCTAssertEqual(result.rows, [[.integer(Int64.max), .real(1.25), .null, .text("Olá 🌱"), .blob(Data([0,255])), .blob(Data()), .text("")]])
    }
    func testParameterBindingCannotInjectSQL() throws {
        let db = try SQLiteDatabase(path: path)
        let text = "x'; DROP TABLE usuarios; --"
        let result = try db.execute("SELECT ?, ?, ?, ?", parameters: [.text(text), .integer(42), .null, .text("a\0b")])
        XCTAssertEqual(result[0].rows, [[.text(text), .integer(42), .null, .text("a\0b")]])
        XCTAssertThrowsError(try db.execute("SELECT ?"))
        XCTAssertEqual(try db.page(object: "usuarios", offset: 0).result.rows.count, 2)
    }
    func testMultipleStatementsAndDuplicateColumnNames() throws {
        let db = try SQLiteDatabase(path: path)
        let results = try db.execute("-- começo\nSELECT 1 AS x, 2 AS x; SELECT 'dois'; -- fim")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].columns, ["x", "x"])
        XCTAssertEqual(results[1].rows, [[.text("dois")]])
        XCTAssertTrue(try db.execute("-- apenas comentário").isEmpty)
        XCTAssertThrowsError(try db.execute("SELECT 1; SELECT inexistente"))
        XCTAssertThrowsError(try db.execute("SELECT 1\0; DELETE FROM usuarios"))
    }
    func testReadOnlyBlocksMutationsAttachmentsAndPragmaBypasses() throws {
        let db = try SQLiteDatabase(path: path)
        let other = directory.appendingPathComponent("should-not-exist.sqlite").path
        for sql in ["DELETE FROM usuarios", "CREATE TABLE bad(id)", "UPDATE usuarios SET nome='bad'", "PRAGMA query_only=OFF", "PRAGMA user_version=42", "PRAGMA writable_schema=ON", "ATTACH DATABASE '\(other)' AS other", "SELECT load_extension('/tmp/example')", "VACUUM INTO '\(other)'"] {
            XCTAssertThrowsError(try db.execute(sql), sql)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: other))
        XCTAssertEqual(try db.execute("SELECT nome FROM usuarios WHERE id=1")[0].rows, [[.text("Ana")]])
        XCTAssertFalse(try db.execute("PRAGMA table_info(usuarios)")[0].rows.isEmpty)
    }
    func testInvalidAndMissingFilesAreNotCreatedOrReplaced() throws {
        let missing = directory.appendingPathComponent("missing.sqlite").path
        XCTAssertThrowsError(try SQLiteDatabase(path: missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing))
        let invalid = directory.appendingPathComponent("invalid.sqlite")
        let bytes = Data("not a sqlite database".utf8)
        try bytes.write(to: invalid)
        XCTAssertThrowsError(try SQLiteDatabase(path: invalid.path).objects())
        XCTAssertEqual(try Data(contentsOf: invalid), bytes)
    }
    func testPagingAndTruncationHaveNoMissingRows() throws {
        try write("CREATE TABLE many(id INTEGER PRIMARY KEY); WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<450) INSERT INTO many SELECT x FROM n")
        let db = try SQLiteDatabase(path: path)
        let first = try db.page(object: "many", offset: 0)
        let second = try db.page(object: "many", offset: 200)
        let third = try db.page(object: "many", offset: 400)
        XCTAssertEqual(first.result.rows.count, 200)
        XCTAssertEqual(second.result.rows.first, [.integer(201)])
        XCTAssertEqual(third.result.rows.count, 50)
        XCTAssertTrue(first.hasNext)
        XCTAssertFalse(third.hasNext)
        let limited = try db.execute("SELECT * FROM many", limit: 10)[0]
        XCTAssertEqual(limited.rows.count, 10)
        XCTAssertTrue(limited.truncated)
        XCTAssertFalse(try db.execute("SELECT * FROM many LIMIT 10", limit: 10)[0].truncated)
    }
    func testCancellationDuringLongQueryAndConnectionReuse() throws {
        let started = expectation(description: "started")
        let finished = expectation(description: "cancelled")
        let flag = QueryCancellation()
        let path = self.path
        DispatchQueue.global().async {
            do {
                let db = try SQLiteDatabase(path: path)
                started.fulfill()
                XCTAssertThrowsError(try db.execute("WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<1000000000) SELECT sum(x) FROM n", cancellation: flag))
                XCTAssertEqual(try db.execute("SELECT 1")[0].rows, [[.integer(1)]])
            } catch { XCTFail(error.localizedDescription) }
            finished.fulfill()
        }
        wait(for: [started], timeout: 3)
        Thread.sleep(forTimeInterval: 0.03)
        flag.cancel()
        wait(for: [finished], timeout: 3)
    }
    func testTimeoutAndMemoryLimits() throws {
        let db = try SQLiteDatabase(path: path)
        XCTAssertThrowsError(try db.execute("WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<1000000000) SELECT sum(x) FROM n", cancellation: QueryCancellation(timeout: 0.02)))
        XCTAssertThrowsError(try db.execute("SELECT zeroblob(1048577)"))
        XCTAssertEqual(try db.execute("SELECT 2")[0].rows, [[.integer(2)]])
    }
    func testLocalPersistenceAndSampleDatabase() async throws {
        let store = LocalStore(directory: directory.appendingPathComponent("state"))
        var state = try await store.load()
        state.saved = [.init(name: "Minha consulta", sql: "SELECT 42")]
        state.history = [.init(sql: "SELECT 42", database: path, status: "Concluída", rowCount: 1, duration: 0.01)]
        state.recentPaths = [path]
        state.draft = "SELECT 'persistido'"
        try await store.save(state)
        let other = LocalStore(directory: directory.appendingPathComponent("state"))
        let restored = try await other.load()
        XCTAssertEqual(restored.saved[0].sql, "SELECT 42")
        XCTAssertEqual(restored.history[0].id, state.history[0].id)
        XCTAssertEqual(restored.recentPaths, [path])
        XCTAssertEqual(restored.draft, state.draft)
        let sample = try await store.sampleDatabase()
        let sampleAgain = try await store.sampleDatabase()
        XCTAssertEqual(sample, sampleAgain)
        let db = try SQLiteDatabase(path: sample.path)
        XCTAssertEqual(try db.objects().count, 5)
        XCTAssertEqual(try db.foreignKeys().count, 3)
        XCTAssertEqual(try db.execute("SELECT COUNT(*) FROM usuarios")[0].rows, [[.integer(4)]])
    }
    func testFailedConnectionKeepsPreviousDatabase() async throws {
        let service = DatabaseService()
        _ = try await service.connect(path: path, cancellation: QueryCancellation())
        do { _ = try await service.connect(path: path + "-missing", cancellation: QueryCancellation()); XCTFail("Should fail") } catch {}
        let result = try await service.execute(sql: "SELECT COUNT(*) FROM usuarios", parameters: [], cancellation: QueryCancellation())
        XCTAssertEqual(result[0].rows, [[.integer(2)]])
    }
}
