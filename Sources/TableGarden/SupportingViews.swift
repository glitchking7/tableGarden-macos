import SwiftUI
import AppKit
import GardenCore

struct SQLTextEditor: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let editor = scroll.documentView as! NSTextView
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.font = NSFont(name: "CascadiaCode-Regular", size: 14)
        editor.textColor = NSColor(Color(hex: 0xE6EDF3))
        editor.insertionPointColor = .systemYellow
        editor.backgroundColor = NSColor(Theme.editor)
        editor.textContainerInset = NSSize(width: 20, height: 20)
        editor.string = text
        editor.delegate = context.coordinator
        editor.isAutomaticTextCompletionEnabled = false
        scroll.drawsBackground = false
        highlight(editor)
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = view.documentView as? NSTextView, editor.string != text else { return }
        editor.string = text
        highlight(editor)
    }
    func highlight(_ editor: NSTextView) {
        let full = NSRange(location: 0, length: (editor.string as NSString).length)
        editor.textStorage?.addAttributes([.foregroundColor: NSColor(Theme.text), .font: NSFont(name: "CascadiaCode-Regular", size: 14)!], range: full)
        let expression = try! NSRegularExpression(pattern: "\\b(SELECT|FROM|WHERE|ORDER BY|GROUP BY|JOIN|ON|AS|LIMIT|COUNT|AND|OR|INSERT|UPDATE|DELETE|SET)\\b", options: [.caseInsensitive])
        for match in expression.matches(in: editor.string, range: full) { editor.textStorage?.addAttribute(.foregroundColor, value: NSColor(Theme.blue), range: match.range) }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLTextEditor
        init(_ parent: SQLTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            parent.highlight(editor)
        }
    }
}

struct RelationshipsView: View {
    @ObservedObject var model: WorkspaceModel
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack { Eyebrow(title: "RELAÇÕES DECLARADAS"); Spacer(); Tag(text: "\(model.foreignKeys.count) vínculos") }
                if model.foreignKeys.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 32)).foregroundStyle(Theme.blue)
                        Text(model.isBusy ? "Lendo as relações…" : "Nenhuma chave estrangeira encontrada.").font(Theme.font(15, .medium))
                        Text("As relações aparecem quando o banco declara FOREIGN KEY. Tabelas podem ter relações lógicas que ainda não foram declaradas.").font(Theme.font(11)).foregroundStyle(Theme.secondary).lineSpacing(5)
                        Button("Atualizar relações") { model.loadRelationships() }.buttonStyle(GardenButton()).disabled(model.isBusy)
                    }.padding(24)
                }
                ForEach(model.foreignKeys) { key in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Label(key.sourceTable, systemImage: "tablecells").foregroundStyle(Theme.blue); Spacer(); Image(systemName: "arrow.right").foregroundStyle(Theme.yellow); Spacer(); Label(key.targetTable, systemImage: "key.horizontal").foregroundStyle(Theme.blue) }.font(Theme.font(13, .medium))
                        Text(key.sourceColumn + " → " + key.targetColumn).font(Theme.font(12)).textSelection(.enabled)
                        Text("A coluna da tabela de origem referencia uma chave da tabela de destino. A cardinalidade depende das restrições de unicidade e dos demais campos da chave.").font(Theme.font(11)).foregroundStyle(Theme.secondary).lineSpacing(5)
                        HStack { Button("Ver origem") { model.select(key.sourceTable) }; Button("Ver destino") { model.select(key.targetTable) } }.buttonStyle(GardenButton()).disabled(model.isBusy)
                    }.padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                }
                Text("O diagrama com zoom e organização automática será acrescentado em uma próxima etapa.").font(Theme.font(10)).foregroundStyle(Theme.secondary)
            }.padding(24)
        }
    }
}

struct ConnectionView: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var engine = "SQLite"
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Label("Abrir banco local", systemImage: "externaldrive.badge.plus").font(Theme.font(21, .bold)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Fechar") }
            Text("Seu próximo jardim começa aqui.").foregroundStyle(Theme.secondary)
            HStack(spacing: 10) {
                ForEach(["SQLite", "PostgreSQL", "MySQL"], id: \.self) { item in
                    Button { engine = item } label: { Text(item).font(Theme.font(12, .medium)).frame(maxWidth: .infinity).padding(14).foregroundStyle(engine == item ? Theme.yellow : Theme.secondary).background(engine == item ? Theme.yellow.opacity(0.12) : Theme.raised, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
                }
            }
            if engine == "SQLite" {
                Label("Somente leitura", systemImage: "lock.shield").foregroundStyle(Theme.yellow)
                Text("Abra um arquivo existente ou crie um banco de exemplo. Consultas, tabelas e chaves são lidas diretamente do arquivo; edições ainda não estão habilitadas.").font(Theme.font(11)).foregroundStyle(Theme.secondary).lineSpacing(5)
                HStack {
                    Button { model.chooseDatabase() } label: { Label("Escolher arquivo…", systemImage: "folder.badge.plus") }.buttonStyle(GardenButton(prominent: true))
                    Button { model.openSample() } label: { Label("Banco de exemplo", systemImage: "leaf") }.buttonStyle(GardenButton())
                }.disabled(model.isBusy || !model.loadedState)
                if !model.recentPaths.isEmpty {
                    Eyebrow(title: "RECENTES")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(model.recentPaths, id: \.self) { path in
                                Button { Task { await model.connect(URL(fileURLWithPath: path)) } } label: { Label(path, systemImage: "externaldrive").font(Theme.font(11)).lineLimit(1).truncationMode(.middle) }.buttonStyle(.plain).foregroundStyle(Theme.blue).disabled(model.isBusy)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 160)
                }
            } else {
                Label("Próxima etapa", systemImage: "wrench.and.screwdriver").foregroundStyle(Theme.yellow)
                Text("O adaptador \(engine) ainda não está implementado. O suporte será adicionado após a consolidação do SQLite e permitirá conectar a um servidor no próprio Mac.").font(Theme.font(11)).foregroundStyle(Theme.secondary).lineSpacing(5)
            }
            if model.isBusy { HStack { ProgressView().controlSize(.small); Text("Abrindo banco…"); Spacer(); Button("Cancelar") { model.cancel() }.buttonStyle(GardenButton()) } }
            if let error = model.error { Text(error).font(Theme.font(11)).foregroundStyle(.orange).textSelection(.enabled) }
        }.padding(30).frame(width: 570).font(Theme.font(12)).foregroundStyle(Theme.text).background(Theme.panel).preferredColorScheme(.dark)
    }
}
