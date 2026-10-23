import SwiftUI
import AppKit
import GardenCore

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 244)
                VStack(spacing: 0) {
                    header
                    if let issue = model.error { banner(issue, color: .orange) }
                    if let issue = model.persistenceError { banner(issue, color: .orange) }
                    HStack(spacing: 0) {
                        Group {
                            if !model.isConnected && ["Tabelas", "Editor SQL", "Relacionamentos"].contains(model.section) { welcome }
                            else if model.section == "Tabelas" { tableContent }
                            else if model.section == "Editor SQL" { queryContent }
                            else if model.section == "Relacionamentos" { RelationshipsView(model: model) }
                            else { libraryContent }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        if model.showInspector && model.isConnected { inspector.frame(width: 260).background(Theme.panel) }
                    }
                }
            }
            footer
        }
        .background(Theme.background).foregroundStyle(Theme.text).font(Theme.font())
        .tint(Theme.blue).preferredColorScheme(.dark)
        .frame(minWidth: 1100, minHeight: 700)
        .sheet(isPresented: $model.showConnection) { ConnectionView(model: model) }
        .task(id: model.sql) {
            do { try await Task.sleep(nanoseconds: 600_000_000); model.persist() } catch {}
        }
    }
    private func banner(_ text: String, color: Color) -> some View {
        HStack(alignment: .top) { Image(systemName: "exclamationmark.circle"); Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true); Spacer() }.font(Theme.font(11)).foregroundStyle(color).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.08))
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(nsImage: Theme.logo).resizable().scaledToFit().frame(width: 55, height: 55).accessibilityHidden(true)
                (Text("table").foregroundColor(Theme.yellow) + Text("Garden").foregroundColor(Theme.blue)).font(Theme.font(21, .bold))
            }.padding(.top, 20).padding(.bottom, 23)
            HStack(spacing: 7) { Circle().fill(Theme.yellow).frame(width: 6, height: 6); Eyebrow(title: "WORKSPACE LOCAL") }.padding(.bottom, 23)
            ForEach([("Tabelas", "tablecells"), ("Editor SQL", "chevron.left.forwardslash.chevron.right"), ("Relacionamentos", "point.3.connected.trianglepath.dotted"), ("Queries salvas", "bookmark"), ("Histórico", "clock.arrow.circlepath")], id: \.0) { title, icon in
                Button { model.navigate(title) } label: {
                    HStack(spacing: 10) { Image(systemName: icon).frame(width: 18); Text(title); Spacer() }
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .foregroundStyle(model.section == title ? Theme.blue : Theme.text)
                        .background(model.section == title ? Theme.blue.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).disabled(model.isBusy && title == "Relacionamentos").padding(.bottom, 3)
            }
            HStack { Eyebrow(title: "BANCO DE DADOS"); Spacer(); Button { model.showConnection = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Abrir conexão") }.padding(.top, 25).padding(.bottom, 14)
            Text(model.databaseName).font(Theme.font(12, .medium)).lineLimit(1).truncationMode(.middle).help(model.databaseURL?.path ?? "Abra um arquivo SQLite")
            if model.isConnected {
                Label("SQLite · somente leitura", systemImage: "lock").font(Theme.font(10)).foregroundStyle(Theme.secondary).padding(.top, 8)
                HStack { Image(systemName: "magnifyingglass"); TextField("Buscar tabelas…", text: $model.search).textFieldStyle(.plain) }.font(Theme.font(11)).foregroundStyle(Theme.secondary).padding(9).background(Theme.panel, in: RoundedRectangle(cornerRadius: 5)).padding(.vertical, 12)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.objects.filter { model.search.isEmpty || $0.name.localizedCaseInsensitiveContains(model.search) }) { object in
                            Button { model.select(object.name) } label: {
                                HStack(spacing: 9) { Image(systemName: object.kind == "view" ? "eye" : "tablecells").foregroundStyle(model.selectedTable == object.name ? Theme.yellow : Theme.secondary); Text(object.name).lineLimit(1); Spacer() }
                                    .font(Theme.font(12)).padding(10).background(model.selectedTable == object.name ? Theme.raised.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            }.buttonStyle(.plain).disabled(model.isBusy)
                        }
                    }
                }
            } else { Text("Nenhum arquivo selecionado").font(Theme.font(10)).foregroundStyle(Theme.secondary).padding(.top, 8); Spacer() }
            VStack(alignment: .leading, spacing: 10) {
                Label("Seu banco. Seu jardim.", systemImage: "leaf").font(Theme.font(11, .medium))
                Text("Explore, pergunte e aprenda.\nTudo fica no seu Mac.").font(Theme.font(10)).foregroundStyle(Theme.secondary).lineSpacing(5)
                Label("100% local", systemImage: "lock.shield").font(Theme.font(10)).foregroundStyle(Theme.blue)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8)).padding(.top, 16)
            Button { model.showConnection = true } label: { Label("Gerenciar conexões", systemImage: "externaldrive.badge.plus").font(Theme.font(11)) }.buttonStyle(.plain).padding(.vertical, 18)
        }.padding(.horizontal, 16).frame(maxHeight: .infinity).background(Theme.sidebar)
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: model.section == "Tabelas" ? "tablecells" : "square.stack.3d.up").foregroundStyle(Theme.blue)
                    Text(model.section == "Tabelas" ? (model.selectedTable.isEmpty ? "Explore seus dados" : model.selectedTable) : model.section).font(Theme.font(23, .bold)).lineLimit(1)
                }
                Text(subtitle).font(Theme.font(11)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small); Button("Cancelar") { model.cancel() }.buttonStyle(GardenButton()) }
            else {
                if model.isConnected { Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Atualizar banco (⌘R)") }
                Button { model.showConnection = true } label: { Label("Abrir banco", systemImage: "folder.badge.plus") }.buttonStyle(GardenButton()).disabled(!model.loadedState)
            }
            Button { model.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.buttonStyle(.plain).foregroundStyle(Theme.secondary).padding(.leading, 8).help("Mostrar ou ocultar inspector")
        }.padding(.horizontal, 26).padding(.vertical, 25)
    }
    private var subtitle: String {
        switch model.section {
        case "Tabelas": return "Explore os dados, uma linha de cada vez."
        case "Editor SQL": return "Consultas reais. Dados que ficam no seu Mac."
        case "Relacionamentos": return "Chaves estrangeiras declaradas no banco."
        case "Queries salvas": return "Suas descobertas, sempre por perto."
        default: return "Consultas persistidas neste Mac · últimas 500."
        }
    }
    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "externaldrive").font(.system(size: 45)).foregroundStyle(Theme.yellow)
                Text("Um banco de dados.\nMuitas descobertas.").font(Theme.font(28, .bold))
                Text("Abra um arquivo SQLite para explorar tabelas, views e relacionamentos, ou escreva sua primeira consulta. Seus arquivos serão abertos somente para leitura.").foregroundStyle(Theme.secondary).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button { model.chooseDatabase() } label: { Label("Abrir SQLite", systemImage: "folder.badge.plus") }.buttonStyle(GardenButton(prominent: true))
                    Button { model.openSample() } label: { Label("Criar banco de exemplo", systemImage: "leaf") }.buttonStyle(GardenButton())
                }.disabled(model.isBusy || !model.loadedState)
                Text("O exemplo cria um arquivo SQLite real, armazenado neste Mac.").font(Theme.font(10)).foregroundStyle(Theme.secondary)
                if !model.recentPaths.isEmpty {
                    Eyebrow(title: "ABERTOS RECENTEMENTE")
                    ForEach(model.recentPaths, id: \.self) { path in
                        Button { Task { await model.connect(URL(fileURLWithPath: path)) } } label: { Label(path, systemImage: "clock").font(Theme.font(11)).lineLimit(1).truncationMode(.middle) }.buttonStyle(.plain).foregroundStyle(Theme.blue).disabled(model.isBusy)
                    }
                }
            }.padding(40).frame(maxWidth: 700, alignment: .leading)
        }.frame(maxWidth: .infinity)
    }
    private var tableContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 22) {
                ForEach(["Dados", "Estrutura"], id: \.self) { tab in
                    Button { model.resultTab = tab } label: { VStack(spacing: 12) { Label(tab, systemImage: tab == "Dados" ? "tablecells" : "list.bullet.indent").font(Theme.font(12)); Rectangle().fill(model.resultTab == tab ? Theme.blue : .clear).frame(height: 2) } }.buttonStyle(.plain).foregroundStyle(model.resultTab == tab ? Theme.text : Theme.secondary)
                }
                Spacer()
                Tag(text: model.selectedObject?.kind == "view" ? "VIEW" : "TABELA")
            }.padding(.horizontal, 24).padding(.top, 12)
            if model.selectedTable.isEmpty {
                Text("Este banco ainda não contém tabelas ou views.").foregroundStyle(Theme.secondary).padding(30); Spacer()
            } else {
                HStack {
                    HStack(spacing: 9) { Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary); TextField("Filtrar nesta página…", text: $model.filter).textFieldStyle(.plain).font(Theme.font(12)) }.padding(11).background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                    Button { model.openQuery("SELECT *\nFROM \(quotedIdentifier(model.selectedTable))\nLIMIT 100;") } label: { Label("Abrir no SQL", systemImage: "chevron.left.forwardslash.chevron.right") }.buttonStyle(GardenButton())
                }.padding(24)
                if model.resultTab == "Estrutura" { structureTable } else { DataGrid(model: model) }
                HStack {
                    Text("\(model.visibleRows.count) linhas · página \(model.offset / 200 + 1)").font(Theme.font(10))
                    Spacer()
                    Button { model.changePage(-1) } label: { Image(systemName: "chevron.left") }.disabled(model.offset == 0 || model.isBusy).help("Página anterior")
                    Button { model.changePage(1) } label: { Image(systemName: "chevron.right") }.disabled(!model.hasNextPage || model.isBusy).help("Próxima página")
                }.buttonStyle(.plain).foregroundStyle(Theme.secondary).padding(.horizontal, 24).padding(.vertical, 15)
                Spacer(minLength: 15)
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Image(systemName: "lightbulb").foregroundStyle(Theme.yellow); Eyebrow(title: "CULTIVE SEU CONHECIMENTO") }
                    Text("Cada linha é um registro. Cada coluna descreve uma informação.").font(Theme.font(12, .medium))
                    Text("A navegação carrega até 200 registros por página. O filtro pesquisa apenas a página carregada; use WHERE no editor para consultar o banco inteiro.").font(Theme.font(11)).foregroundStyle(Theme.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    Button { model.navigate("Relacionamentos") } label: { Label("Entender os relacionamentos", systemImage: "arrow.up.right") }.buttonStyle(.plain).foregroundStyle(Theme.blue).font(Theme.font(11))
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8)).padding(24)
            }
        }
    }
    private var structureTable: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.columns) { column in
                    HStack { Image(systemName: column.primaryKeyPosition > 0 ? "key.horizontal" : "number").foregroundStyle(column.primaryKeyPosition > 0 ? Theme.yellow : Theme.secondary).frame(width: 24); VStack(alignment: .leading, spacing: 5) { Text(column.name); if let value = column.defaultValue { Text("Padrão: \(value)").foregroundStyle(Theme.secondary).font(Theme.font(10)) } }; Spacer(); Text(column.type + (column.notNull ? " · NOT NULL" : "") + (column.primaryKeyPosition > 0 ? " · PK \(column.primaryKeyPosition)" : "")).foregroundStyle(Theme.secondary) }.font(Theme.font(11)).padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 5))
                }
                Eyebrow(title: "ÍNDICES")
                ForEach(model.indexes, id: \.self) { Text($0).font(Theme.font(11)).foregroundStyle(Theme.blue) }
                if model.indexes.isEmpty { Text("Nenhum índice listado.").font(Theme.font(11)).foregroundStyle(Theme.secondary) }
                Eyebrow(title: "DEFINIÇÃO SQL")
                Text(model.selectedObject?.ddl ?? "").font(Theme.font(11)).textSelection(.enabled).lineSpacing(5)
            }.padding(.horizontal, 24)
        }.frame(maxHeight: 400)
    }
    private var queryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label("consulta.sql", systemImage: "doc.text").font(Theme.font(12)); Spacer(); Tag(text: "SOMENTE LEITURA", color: Theme.yellow) }
            SQLTextEditor(text: $model.sql).frame(minHeight: 130, idealHeight: 180, maxHeight: 220).background(Theme.editor, in: RoundedRectangle(cornerRadius: 8))
            HStack { Text("Parâmetros").foregroundStyle(Theme.secondary); TextField("Lista JSON: [1, \"Ana\", null]", text: $model.parameterText).textFieldStyle(.plain).padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 5)) }.font(Theme.font(11))
            HStack {
                Button { model.executeQuery() } label: { Label("Executar SQL", systemImage: "play.fill") }.buttonStyle(GardenButton(prominent: true)).keyboardShortcut(.return, modifiers: .command).disabled(model.isBusy)
                Button { model.saveQuery() } label: { Label("Salvar query", systemImage: "bookmark") }.buttonStyle(GardenButton()).disabled(!model.loadedState)
                Spacer(); Text("⌘ ↵").foregroundStyle(Theme.secondary).font(Theme.font(11))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if model.results.isEmpty {
                        VStack(spacing: 12) { Image(systemName: "terminal").font(.system(size: 26)).foregroundStyle(Theme.blue); Text(model.isBusy ? "Consultando seu banco…" : "Toda descoberta começa com uma pergunta.").font(Theme.font(12)); Text("Até 10 comandos de leitura · 1.000 linhas por resultado.").font(Theme.font(10)).foregroundStyle(Theme.secondary) }.frame(maxWidth: .infinity).padding(30)
                    }
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Eyebrow(title: "RESULTADO \(index + 1)"); Spacer(); Text(String(format: "%.1f ms", result.duration * 1000)).font(Theme.font(10)).foregroundStyle(Theme.secondary); Tag(text: "\(result.rows.count) linhas", color: Theme.green) }
                            ResultGrid(columns: result.columns, rows: result.rows)
                            if result.truncated { Text("Resultado limitado às primeiras 1.000 linhas. Refine a consulta ou use LIMIT/OFFSET.").foregroundStyle(Theme.yellow).font(Theme.font(10)) }
                        }
                    }
                }
            }
        }.padding(24)
    }
    private var libraryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if model.section == "Queries salvas" {
                    if model.saved.isEmpty { Text("Salve sua primeira consulta pelo editor SQL.").foregroundStyle(Theme.secondary).padding(20) }
                    ForEach(model.saved) { query in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Image(systemName: "bookmark").foregroundStyle(Theme.yellow); Text(query.name).font(Theme.font(14, .medium)); Spacer(); Button { model.openQuery(query.sql) } label: { Image(systemName: "arrow.up.right") }.help("Abrir no editor"); Button { model.deleteSaved(query.id) } label: { Image(systemName: "trash") }.help("Excluir consulta salva") }.buttonStyle(.plain)
                            Text(query.sql).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(4).textSelection(.enabled)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                } else if model.history.isEmpty {
                    VStack(spacing: 15) { Image(systemName: "clock.arrow.circlepath").font(.system(size: 30)).foregroundStyle(Theme.blue); Text("Seu histórico começa aqui.").font(Theme.font(16, .medium)); Text("Consultas executadas e erros ficam salvos neste Mac.").foregroundStyle(Theme.secondary).font(Theme.font(11)) }.frame(maxWidth: .infinity).padding(.top, 100)
                } else {
                    ForEach(model.history) { item in
                        Button { model.openQuery(item.sql) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Tag(text: item.status, color: item.error == nil ? Theme.green : .orange); Spacer(); Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(Theme.font(10)).foregroundStyle(Theme.secondary) }
                                Text(item.sql).font(Theme.font(12)).lineLimit(5)
                                Text(URL(fileURLWithPath: item.database).lastPathComponent + " · \(item.rowCount) linhas · " + String(format: "%.1f ms", item.duration * 1000)).font(Theme.font(10)).foregroundStyle(Theme.secondary)
                                if let error = item.error { Text(error).foregroundStyle(.orange).font(Theme.font(10)) }
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(24)
        }
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label(model.section == "Editor SQL" ? "Sobre a execução" : "Inspector", systemImage: "sidebar.right").font(Theme.font(14, .medium))
                if model.section == "Editor SQL" {
                    Label("Execução real", systemImage: "checkmark.circle").foregroundStyle(Theme.green)
                    Text("O SQL é executado pelo SQLite no arquivo aberto. Nenhum dado é enviado a serviços externos.").font(Theme.font(11)).foregroundStyle(Theme.secondary).lineSpacing(5)
                    Eyebrow(title: "RESULTADOS")
                    Text("\(model.results.count)").font(Theme.font(24, .medium))
                    Text("Cada comando mostra seu próprio resultado. Consultas muito grandes são limitadas para preservar a memória.").font(Theme.font(11)).foregroundStyle(Theme.secondary).lineSpacing(5)
                    Eyebrow(title: "PARÂMETROS")
                    Text("Use ? ou ?1 no SQL e informe uma lista JSON abaixo do editor. Exemplo: WHERE id = ? com [1]. A mesma lista é vinculada a cada comando.").font(Theme.font(11)).foregroundStyle(Theme.secondary).lineSpacing(5)
                    Tag(text: "SQLITE · LEITURA", color: Theme.yellow)
                    Text("Explicações automáticas e planos de execução serão acrescentados em uma próxima etapa.").font(Theme.font(11)).foregroundStyle(Theme.secondary).lineSpacing(5)
                } else {
                    Eyebrow(title: "OBJETO SELECIONADO")
                    Text(model.selectedTable.isEmpty ? "Nenhuma tabela" : model.selectedTable).font(Theme.font(15, .medium))
                    HStack { metric("NA PÁGINA", "\(model.table.rows.count)"); Spacer(); metric("COLUNAS", "\(model.table.columns.count)") }
                    Eyebrow(title: "REGISTRO")
                    if let index = model.selectedRow, model.table.rows.indices.contains(index) {
                        ForEach(Array(model.table.columns.enumerated()), id: \.offset) { i, col in
                            VStack(alignment: .leading, spacing: 8) { HStack { Text(col).foregroundStyle(Theme.secondary); Spacer(); if model.primaryKeys.contains(col) { Image(systemName: "key.horizontal").foregroundStyle(Theme.yellow) } }.font(Theme.font(10)); Text(model.table.rows[index][i]).font(Theme.font(12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                        }
                    } else { Text("Selecione uma linha para explorar os campos.").font(Theme.font(11)).foregroundStyle(Theme.secondary).lineSpacing(5) }
                    VStack(alignment: .leading, spacing: 12) { Label("Chave primária", systemImage: "key.horizontal").foregroundStyle(Theme.yellow).font(Theme.font(11, .medium)); Text(model.primaryKeys.isEmpty ? "Este objeto não declara uma chave primária." : "Identifica cada registro. Campos: " + model.columns.filter { $0.primaryKeyPosition > 0 }.map(\.name).joined(separator: ", ")).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineSpacing(5) }.padding(14).background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                }
                Text(model.databaseURL?.path ?? "").font(Theme.font(9)).foregroundStyle(Theme.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(Theme.font(9)).foregroundStyle(Theme.secondary); Text(value).font(Theme.font(24, .medium)) } }
    private var footer: some View {
        HStack(spacing: 20) { Label("100% local", systemImage: "lock.shield").foregroundStyle(Theme.blue); Label(model.databaseName, systemImage: "externaldrive").lineLimit(1); if !model.notice.isEmpty { Text(model.notice).foregroundStyle(Theme.yellow).lineLimit(1) }; Spacer(); Text("macOS / v0.2.0") }.font(Theme.font(10)).foregroundStyle(Theme.secondary).padding(.horizontal, 20).frame(height: 33).background(Theme.sidebar)
    }
}

struct DataGrid: View {
    @ObservedObject var model: WorkspaceModel
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("#").frame(width: 45)
                    ForEach(Array(model.table.columns.enumerated()), id: \.offset) { _, column in HStack(spacing: 5) { if model.primaryKeys.contains(column) { Image(systemName: "key.horizontal").foregroundStyle(Theme.yellow) }; Text(column).lineLimit(1); Spacer() }.frame(width: 170).padding(.horizontal, 10) }
                }.font(Theme.font(11, .medium)).foregroundStyle(Theme.secondary).frame(height: 38).background(Theme.raised)
                ForEach(model.visibleRows, id: \.offset) { index, row in
                    Button { model.selectedRow = index } label: {
                        HStack(spacing: 0) { Text(String(model.offset + index + 1)).foregroundStyle(Theme.secondary).frame(width: 45); ForEach(Array(row.enumerated()), id: \.offset) { i, value in Text(value).foregroundStyle(model.primaryKeys.contains(model.table.columns[i]) ? Theme.yellow : Theme.text).frame(width: 170, alignment: .leading).padding(.horizontal, 10).lineLimit(1).help(value) } }.font(Theme.font(11)).frame(height: 40).background(model.selectedRow == index ? Theme.blue.opacity(0.14) : (index % 2 == 0 ? Theme.surface.opacity(0.65) : Theme.background))
                    }.buttonStyle(.plain).accessibilityLabel("Registro \(model.offset + index + 1): \(row.joined(separator: ", "))")
                }
                if model.visibleRows.isEmpty { Text(model.isBusy ? "Carregando…" : "Nenhum registro nesta página.").foregroundStyle(Theme.secondary).padding(24) }
            }
        }.defaultScrollAnchor(.topLeading).frame(height: min(CGFloat(max(1, model.visibleRows.count)) * 40 + 52, 375)).clipShape(RoundedRectangle(cornerRadius: 6)).padding(.horizontal, 24)
    }
}

struct ResultGrid: View {
    let columns: [String]
    let rows: [[SQLValue]]
    var body: some View {
        ScrollView(.horizontal) {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) { ForEach(Array(columns.enumerated()), id: \.offset) { _, name in Text(name).frame(width: 190, alignment: .leading).padding(10) } }.foregroundStyle(Theme.secondary).background(Theme.raised)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 0) { ForEach(Array(row.enumerated()), id: \.offset) { _, value in Text(value.display).foregroundStyle(value == .null ? Theme.secondary : Theme.text).lineLimit(2).frame(width: 190, alignment: .leading).padding(10).textSelection(.enabled).help(value.display) } }.background(index % 2 == 0 ? Theme.surface : Theme.background)
                }
                if rows.isEmpty { Text("Nenhuma linha retornada.").foregroundStyle(Theme.secondary).padding(15) }
            }.font(Theme.font(11))
        }.clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
