import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first, CommandLineTool.commands.contains(first) {
            CommandLineTool.run(args)
        }
        LookdownApp.main()
    }
}

struct LookdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Lookdown", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1180, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Test hook: LOOKDOWN_UI_SNAPSHOT=/path/out.png saves the window as a PNG and quits.
        // LOOKDOWN_UI_APPEARANCE=light|dark forces the appearance first.
        let env = ProcessInfo.processInfo.environment
        guard let path = env["LOOKDOWN_UI_SNAPSHOT"] else { return }
        if let look = env["LOOKDOWN_UI_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}
