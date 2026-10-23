import Foundation
import CSQLite

public actor LocalStore {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> LocalState {
        try access { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT payload FROM app_state WHERE id=1", -1, &stmt, nil) == SQLITE_OK else { throw SQLiteFailure("Não foi possível ler as preferências locais.") }
            defer { sqlite3_finalize(stmt) }
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { return LocalState() }
            guard step == SQLITE_ROW, let pointer = sqlite3_column_blob(stmt, 0) else { throw SQLiteFailure("O estado local não pôde ser lido.") }
            let data = Data(bytes: pointer, count: Int(sqlite3_column_bytes(stmt, 0)))
            let state = try JSONDecoder().decode(LocalState.self, from: data)
            guard state.version == 1 else { throw SQLiteFailure("A versão dos dados locais não é compatível. O arquivo foi preservado.") }
            return state
        }
    }
    public func save(_ state: LocalState) throws {
        let data = try JSONEncoder().encode(state)
        try access { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT INTO app_state(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", -1, &stmt, nil) == SQLITE_OK else { throw SQLiteFailure("Não foi possível preparar o salvamento local.") }
            defer { sqlite3_finalize(stmt) }
            let code = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard code == SQLITE_OK, sqlite3_step(stmt) == SQLITE_DONE else { throw SQLiteFailure("Não foi possível salvar os dados locais: \(String(cString: sqlite3_errmsg(db)))") }
        }
    }
    private func access<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var db: OpaquePointer?
        let code = sqlite3_open_v2(directory.appendingPathComponent("tablegarden.sqlite").path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let db else { sqlite3_close(db); throw SQLiteFailure("Não foi possível abrir o armazenamento local.") }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1500)
        guard sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS app_state(id INTEGER PRIMARY KEY CHECK(id=1),payload BLOB NOT NULL)", nil, nil, nil) == SQLITE_OK else { throw SQLiteFailure("Não foi possível preparar o armazenamento local.") }
        return try operation(db)
    }
    public func sampleDatabase() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Jardim de exemplo.sqlite")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let temporary = directory.appendingPathComponent("sample-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: temporary) }
        var db: OpaquePointer?
        guard sqlite3_open(temporary.path, &db) == SQLITE_OK else { sqlite3_close(db); throw SQLiteFailure("Não foi possível criar o banco de exemplo.") }
        let sql = """
        BEGIN;
        PRAGMA foreign_keys=ON;
        CREATE TABLE usuarios(id INTEGER PRIMARY KEY, nome TEXT NOT NULL, email TEXT UNIQUE, cidade TEXT, ativo BOOLEAN DEFAULT 1);
        CREATE TABLE produtos(id INTEGER PRIMARY KEY, nome TEXT NOT NULL, preco REAL, estoque INTEGER);
        CREATE TABLE pedidos(id INTEGER PRIMARY KEY, usuario_id INTEGER REFERENCES usuarios(id), total REAL, status TEXT);
        CREATE TABLE itens_pedido(id INTEGER PRIMARY KEY, pedido_id INTEGER REFERENCES pedidos(id), produto_id INTEGER REFERENCES produtos(id), quantidade INTEGER);
        INSERT INTO usuarios VALUES(1,'Ana Martins','ana@exemplo.local','São Paulo',1),(2,'Bruno Costa','bruno@exemplo.local','Curitiba',1),(3,'Carla Souza',NULL,'Recife',0),(4,'Diego Lima','diego@exemplo.local','São Paulo',1);
        INSERT INTO produtos VALUES(1,'Caderno',29.90,42),(2,'Mochila',149.90,18),(3,'Caneta',9.90,120);
        INSERT INTO pedidos VALUES(101,1,149.90,'concluído'),(102,2,89.00,'pendente'),(103,1,239.50,'concluído'),(104,4,59.90,'enviado');
        INSERT INTO itens_pedido VALUES(1,101,2,1),(2,102,1,3),(3,103,3,5);
        CREATE INDEX pedidos_usuario ON pedidos(usuario_id);
        CREATE VIEW usuarios_ativos AS SELECT nome,email,cidade FROM usuarios WHERE ativo=1;
        COMMIT;
        """
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Erro SQLite"
        sqlite3_close(db)
        guard code == SQLITE_OK else { throw SQLiteFailure(message) }
        try FileManager.default.moveItem(at: temporary, to: url)
        return url
    }
}
