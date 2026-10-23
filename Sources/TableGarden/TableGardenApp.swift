import SwiftUI
import AppKit
import GardenCore

@main struct TableGardenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { Text("tableGarden · SQLite local · v0.2.0").font(Theme.font(13)).padding(30) }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Abrir SQLite…") { delegate.model.chooseDatabase() }.keyboardShortcut("o").disabled(delegate.model.isBusy)
                Button("Atualizar banco") { delegate.model.refresh() }.keyboardShortcut("r").disabled(delegate.model.isBusy || !delegate.model.isConnected)
            }
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    let model: WorkspaceModel = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--snapshot") {
            return WorkspaceModel(directory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tablegarden-preview"), ephemeral: true)
        }
        return WorkspaceModel()
    }()
    private var terminating = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerFonts()
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"), let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        let args = ProcessInfo.processInfo.arguments
        
        let view = WorkspaceView(model: model)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "tableGarden"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.sidebar)
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 1100, height: 740)
        window.contentView = host
        window.center()
        window.setFrameAutosaveName("TableGardenWorkspace")
        self.window = window
        Task {
            await model.bootstrap()
            if let index = args.firstIndex(of: "--database"), args.indices.contains(index + 1) { await model.connect(URL(fileURLWithPath: args[index + 1])) }
            if args.contains("--snapshot") {
                if !model.isConnected {
                    do { let store = LocalPreviewStore(); let url = try await store.sample(); await model.connect(url) } catch { print(error); exit(1) }
                }
                if args.contains("--query-preview") { model.openQuery("SELECT nome, email, cidade\nFROM usuarios\nWHERE ativo = 1\nORDER BY nome;"); model.executeQuery() }
            }
            if let index = args.firstIndex(of: "--section"), args.indices.contains(index + 1) { model.navigate(args[index + 1]) }
            if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) {
                while model.isBusy { try? await Task.sleep(nanoseconds: 30_000_000) }
                let path = args[index + 1]
                host.frame = NSRect(x: 0, y: 0, width: 1380, height: 820)
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                host.cacheDisplay(in: host.bounds, to: rep)
                guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
                do { try data.write(to: URL(fileURLWithPath: path)); print("Snapshot: \(path)"); terminating = true; NSApp.terminate(nil) } catch { print(error); exit(1) }
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateNow }
        model.cancel()
        Task {
            while model.isBusy { try? await Task.sleep(nanoseconds: 20_000_000) }
            await model.flush()
            if model.persistenceError != nil {
                let alert = NSAlert()
                alert.messageText = "Não foi possível salvar os dados locais"
                alert.informativeText = model.persistenceError! + " Você pode voltar ao aplicativo ou encerrar sem salvar as últimas alterações."
                alert.addButton(withTitle: "Voltar")
                alert.addButton(withTitle: "Encerrar sem salvar")
                if alert.runModal() == .alertFirstButtonReturn { sender.reply(toApplicationShouldTerminate: false); return }
            }
            terminating = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window?.makeKeyAndOrderFront(nil); return true }
}

private struct LocalPreviewStore {
    func sample() async throws -> URL {
        try await LocalStore(directory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tablegarden-preview")).sampleDatabase()
    }
}
