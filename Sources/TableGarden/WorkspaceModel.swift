import SwiftUI
import AppKit
import GardenCore

struct GardenTable: Identifiable {
    let name: String
    var columns: [String] = []
    var types: [String] = []
    var rows: [[String]] = []
    var id: String { name }
}
@MainActor final class WorkspaceModel: ObservableObject {
    @Published var section = "Tabelas"
    @Published var selectedTable = ""
    @Published var search = ""
    @Published var filter = ""
    @Published var selectedRow: Int?
    @Published var showConnection = false
    @Published var showInspector = true
    @Published var sql = "SELECT sqlite_version() AS versao;"
    @Published var saved: [SavedQuery] = []
    @Published var history: [QueryRun] = []
    @Published var notice = ""
    @Published var error: String?
    @Published var resultTab = "Dados"
    @Published var tables: [GardenTable] = []
    @Published var objects: [DatabaseObject] = []
    @Published var columns: [ColumnInfo] = []
    @Published var indexes: [String] = []
    @Published var results: [QueryResult] = []
    @Published var foreignKeys: [ForeignKey] = []
    @Published var databaseURL: URL?
    @Published var recentPaths: [String] = []
    @Published var isBusy = false
    @Published var offset = 0
    @Published var hasNextPage = false
    @Published var parameterText = ""
    @Published var persistenceError: String?
    @Published var loadedState = false
    private let service = DatabaseService()
    private let store: LocalStore
    private var cancellation: QueryCancellation?
    private var pageTask: Task<Void, Never>?
    private var stateWritable = false
    private let ephemeral: Bool
    var databaseName: String { databaseURL?.deletingPathExtension().lastPathComponent ?? "Nenhum banco aberto" }
    var isConnected: Bool { databaseURL != nil }
    var table: GardenTable { tables.first { $0.name == selectedTable } ?? GardenTable(name: "") }
    var visibleRows: [(offset: Int, element: [String])] { Array(table.rows.enumerated()).filter { filter.isEmpty || $0.element.joined(separator: " ").localizedCaseInsensitiveContains(filter) } }
    var selectedObject: DatabaseObject? { objects.first { $0.name == selectedTable } }
    var queryPreview: Bool { !results.isEmpty }
    var primaryKeys: Set<String> { Set(columns.filter { $0.primaryKeyPosition > 0 }.map(\.name)) }
    var busyDescription: String { isBusy ? "Operação em andamento…" : "Pronto" }

    init(directory: URL? = nil, ephemeral: Bool = false) {
        self.ephemeral = ephemeral
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("tableGarden", isDirectory: true)
        store = LocalStore(directory: base)
    }
    func bootstrap() async {
        guard !loadedState else { return }
        do {
            let state = try await store.load()
            saved = state.saved; history = state.history; recentPaths = state.recentPaths; sql = state.draft
            if saved.isEmpty, let old = UserDefaults.standard.data(forKey: "savedQueries"), let migrated = try? JSONDecoder().decode([SavedQuery].self, from: old) { saved = migrated }
            stateWritable = true
        } catch { persistenceError = "Armazenamento local: \(error.localizedDescription)" }
        loadedState = true
    }
    func persist() {
        guard loadedState, stateWritable, !ephemeral else { return }
        var state = LocalState()
        state.saved = saved; state.history = Array(history.prefix(500)); state.recentPaths = recentPaths; state.draft = sql
        Task { do { try await store.save(state); persistenceError = nil } catch { persistenceError = "Não foi possível salvar: \(error.localizedDescription)" } }
    }
    func chooseDatabase() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Abrir banco SQLite"
        panel.message = "O arquivo será aberto somente para leitura."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { Task { await connect(url) } }
    }
    func openSample() {
        guard !isBusy else { return }
        Task {
            do { let url = try await store.sampleDatabase(); await connect(url) }
            catch { self.error = error.localizedDescription }
        }
    }
    func connect(_ url: URL) async {
        guard !isBusy else { return }
        let flag = beginOperation()
        defer { endOperation() }
        do {
            let found = try await service.connect(path: url.path, cancellation: flag)
            databaseURL = url; objects = found; tables = found.map { GardenTable(name: $0.name) }
            columns = []; indexes = []; results = []; foreignKeys = []; selectedRow = nil
            selectedTable = found.first?.name ?? ""; offset = 0; hasNextPage = false; filter = ""
            recentPaths.removeAll { $0 == url.path }; recentPaths.insert(url.path, at: 0); recentPaths = Array(recentPaths.prefix(12))
            showConnection = false; section = "Tabelas"; error = nil
            notice = "SQLite aberto somente para leitura."
            persist()
            if !selectedTable.isEmpty { try await loadPage(flag: flag) }
        } catch { self.error = "Não foi possível abrir ou ler o banco: \(error.localizedDescription)" }
    }
    func select(_ table: String) {
        guard !isBusy else { return }
        selectedTable = table; selectedRow = nil; filter = ""; offset = 0; section = "Tabelas"
        fetchPage()
    }
    func changePage(_ delta: Int) { guard !isBusy else { return }; offset = max(0, offset + delta * 200); selectedRow = nil; filter = ""; fetchPage() }
    func refresh() { guard let url = databaseURL, !isBusy else { return }; Task { await connect(url) } }
    private func loadPage(flag: QueryCancellation) async throws {
        let page = try await service.page(object: selectedTable, offset: offset, cancellation: flag)
        columns = page.columns; indexes = page.indexes; hasNextPage = page.hasNext
        if let index = tables.firstIndex(where: { $0.name == selectedTable }) {
            tables[index] = GardenTable(name: selectedTable, columns: page.result.columns, types: page.result.columns.map { name in page.columns.first { $0.name == name }.map { $0.type + ($0.primaryKeyPosition > 0 ? " · PK" : "") + ($0.notNull ? " · NOT NULL" : "") } ?? "" }, rows: page.result.rows.map { $0.map(\.display) })
        }
    }
    private func fetchPage() {
        // Clear old records before requesting a new page, so failed reads never show stale data.
        columns = []; indexes = []; hasNextPage = false
        if let index = tables.firstIndex(where: { $0.name == selectedTable }) { tables[index] = GardenTable(name: selectedTable) }
        let flag = beginOperation()
        pageTask = Task {
            defer { endOperation() }
            do { try await loadPage(flag: flag) } catch { self.error = error.localizedDescription }
        }
    }
    func cancel() { cancellation?.cancel(); notice = "Cancelamento solicitado…" }
    private func beginOperation() -> QueryCancellation { let flag = QueryCancellation(); cancellation = flag; isBusy = true; notice = ""; error = nil; return flag }
    private func endOperation() { isBusy = false; cancellation = nil }
    func executeQuery() {
        guard isConnected, !isBusy, !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let query = sql
        let database = databaseURL!.path
        let parameters: [SQLValue]
        do {
            if parameterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parameters = [] }
            else {
                guard let data = parameterText.data(using: .utf8), let values = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any] else { throw SQLiteFailure("Informe os parâmetros como uma lista JSON: [1, \"Ana\", null].") }
                parameters = try values.map { value in
                    if value is NSNull { return .null }
                    if let text = value as? String { return .text(text) }
                    if let number = value as? NSNumber {
                        if CFGetTypeID(number) == CFBooleanGetTypeID() { return .integer(number.boolValue ? 1 : 0) }
                        if String(cString: number.objCType).contains("f") || String(cString: number.objCType).contains("d") { return .real(number.doubleValue) }
                        if String(cString: number.objCType) == "Q", number.uint64Value > UInt64(Int64.max) { throw SQLiteFailure("Um parâmetro inteiro excede 64 bits com sinal. Informe-o como texto se precisar preservar todos os dígitos.") }
                        return .integer(number.int64Value)
                    }
                    throw SQLiteFailure("Parâmetros aceitam textos, números, booleanos ou null.")
                }
            }
        } catch { self.error = error.localizedDescription; return }
        let flag = beginOperation()
        results = []
        let started = Date()
        Task {
            defer { endOperation(); persist() }
            do {
                results = try await service.execute(sql: query, parameters: parameters, cancellation: flag)
                let count = results.reduce(0) { $0 + $1.rows.count }
                history.insert(.init(sql: query, database: database, status: "Concluída", rowCount: count, duration: Date().timeIntervalSince(started)), at: 0)
                notice = results.isEmpty ? "Nenhum comando SQL encontrado." : "\(results.count) resultado(s) · \(count) linhas carregadas."
            } catch {
                self.error = error.localizedDescription
                history.insert(.init(sql: query, database: database, status: flag.shouldStop ? "Cancelada" : "Erro", rowCount: 0, duration: Date().timeIntervalSince(started), error: error.localizedDescription), at: 0)
            }
            history = Array(history.prefix(500))
        }
    }
    func loadRelationships() {
        guard isConnected, !isBusy else { return }
        let flag = beginOperation()
        foreignKeys = []
        Task { defer { endOperation() }; do { foreignKeys = try await service.foreignKeys(cancellation: flag) } catch { self.error = error.localizedDescription } }
    }
    func navigate(_ title: String) { section = title; if title == "Relacionamentos" { loadRelationships() } }
    func saveQuery() {
        guard loadedState, !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard stateWritable else { error = "O armazenamento local está indisponível. A consulta não foi salva."; return }
        saved.append(.init(name: "Consulta \(saved.count + 1)", sql: sql)); persist(); notice = "Consulta salva neste Mac."
    }
    func deleteSaved(_ id: UUID) { saved.removeAll { $0.id == id }; persist() }
    func openQuery(_ query: String) { sql = query; results = []; parameterText = ""; section = "Editor SQL" }
    func previewQuery() { executeQuery() }
    func flush() async { // Called before termination so the last editor changes survive closing the app.
        guard loadedState, stateWritable, !ephemeral else { return }
        var state = LocalState(); state.saved = saved; state.history = Array(history.prefix(500)); state.recentPaths = recentPaths; state.draft = sql
        do { try await store.save(state) } catch { persistenceError = error.localizedDescription }
    }
}
