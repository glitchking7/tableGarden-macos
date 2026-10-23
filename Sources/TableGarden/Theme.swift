import SwiftUI
import AppKit
import CoreText

enum Theme {
    static let background = Color(hex: 0x161B22)
    static let surface = Color(hex: 0x1C222B)
    static let editor = Color(hex: 0x11161D)
    static let sidebar = Color(hex: 0x090F17)
    static let panel = Color(hex: 0x161B22)
    static let raised = Color(hex: 0x21262D)
    static let text = Color(hex: 0xE6EDF3)
    static let secondary = Color(hex: 0x8B949E)
    static let yellow = Color(hex: 0xFFD029)
    static let blue = Color(hex: 0x159CFA)
    static let green = Color(hex: 0x65C998)
    static let resources: URL = {
        let bundled = Bundle.main.resourceURL!.appendingPathComponent("TableGarden_TableGarden.bundle/Resources")
        return FileManager.default.fileExists(atPath: bundled.path) ? bundled : Bundle.module.resourceURL!.appendingPathComponent("Resources")
    }()
    static func font(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        .custom("CascadiaCode-Regular", size: size).weight(weight)
    }
    static func registerFonts() {
        let url = resources.appendingPathComponent("Fonts/CascadiaCode.ttf")
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        precondition(NSFont(name: "CascadiaCode-Regular", size: 13) != nil, "Cascadia Code precisa acompanhar o aplicativo.")
    }
    static var logo: NSImage { NSImage(contentsOf: resources.appendingPathComponent("Branding/logo-sidebar.png"))! }
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, opacity: 1) }
}
struct GardenButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.font(12, .medium))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .foregroundStyle(prominent ? Theme.sidebar : Theme.text)
            .background(prominent ? Theme.yellow.opacity(configuration.isPressed ? 0.7 : 1) : Theme.raised.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 6))
    }
}
struct Eyebrow: View {
    let title: String
    var body: some View { Text(title).font(Theme.font(10, .medium)).tracking(1.5).foregroundStyle(Theme.secondary) }
}
struct Tag: View {
    let text: String
    var color: Color = Theme.blue
    var body: some View { Text(text).font(Theme.font(10, .medium)).foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 4).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4)) }
}
