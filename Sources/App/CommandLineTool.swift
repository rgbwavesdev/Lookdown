import AppKit
import QuickLookUI
import WebKit

/// Command-line modes of the app binary, for checking output without Quick Look:
///
///   Lookdown --render <file.md> [-o out.html] [options]
///   Lookdown --snapshot <file.md> <out.png> [--size 920x1040] [--full] [options]
///
/// Options override the saved settings: --theme warm|clean|github, --appearance system|light|dark,
/// --font-size N, --width narrow|medium|wide|full, --soft-breaks, --properties shown|collapsed|hidden,
/// --no-remote-images.
enum CommandLineTool {
    static let commands: Set<String> = ["--render", "--snapshot", "--quicklook", "--help"]

    static func run(_ args: [String]) -> Never {
        if args[0] == "--quicklook", args.count >= 2 {
            QuickLookProbe(file: URL(fileURLWithPath: args[1]),
                           seconds: args.count >= 3 ? Double(args[2]) ?? 6 : 6).run()
        }
        var settings = SettingsStore.load()
        var positional: [String] = []
        var output: String?
        var size = CGSize(width: 920, height: 1040)
        var fullPage = false
        var i = 1
        func value() -> String {
            i += 1
            guard i < args.count else { fail("missing value for \(args[i - 1])") }
            return args[i]
        }
        while i < args.count {
            switch args[i] {
            case "-o": output = value()
            case "--theme": settings.theme = LookdownSettings.Theme(rawValue: value()) ?? settings.theme
            case "--appearance": settings.appearance = LookdownSettings.Appearance(rawValue: value()) ?? settings.appearance
            case "--font-size": settings.fontSize = Double(value()) ?? settings.fontSize
            case "--width": settings.width = LookdownSettings.Width(rawValue: value()) ?? settings.width
            case "--soft-breaks": settings.softBreaks = true
            case "--properties": settings.properties = LookdownSettings.Properties(rawValue: value()) ?? settings.properties
            case "--no-remote-images": settings.remoteImages = false
            case "--full": fullPage = true
            case "--size":
                let parts = value().split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 { size = CGSize(width: parts[0], height: parts[1]) }
            default: positional.append(args[i])
            }
            i += 1
        }

        if args[0] == "--help" || positional.isEmpty {
            print("""
            usage: Lookdown --render <file.md> [-o out.html] [options]
                   Lookdown --snapshot <file.md> <out.png> [--size WxH] [--full] [options]
            options: --theme warm|clean|github  --appearance system|light|dark  --font-size N
                     --width narrow|medium|wide|full  --soft-breaks  --properties shown|collapsed|hidden
                     --no-remote-images
            """)
            exit(positional.isEmpty && args[0] != "--help" ? 2 : 0)
        }

        let input = URL(fileURLWithPath: positional[0])
        let renderer = MarkdownRenderer(resources: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
        let started = Date()
        let html: String
        do {
            html = try renderer.page(for: input, settings: settings)
        } catch {
            fail("can't read \(input.path): \(error.localizedDescription)")
        }
        let elapsed = Date().timeIntervalSince(started)

        if args[0] == "--render" {
            if let output {
                do { try html.write(toFile: output, atomically: true, encoding: .utf8) } catch { fail("\(error)") }
                FileHandle.standardError.write(Data(String(format: "rendered in %.0f ms\n", elapsed * 1000).utf8))
            } else {
                print(html)
            }
            exit(0)
        }

        guard positional.count >= 2 else { fail("--snapshot needs an output .png path") }
        let dark: Bool
        switch settings.appearance {
        case .light: dark = false
        case .dark: dark = true
        case .system: dark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        let snapshotter = Snapshotter(html: html, size: size, fullPage: fullPage, dark: dark,
                                      output: URL(fileURLWithPath: positional[1]))
        withExtendedLifetime(snapshotter) { snapshotter.run() }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Lookdown: \(message)\n".utf8))
        exit(1)
    }
}

/// Renders a page in an off-screen WKWebView (the engine Quick Look uses) and saves a PNG.
final class Snapshotter: NSObject, WKNavigationDelegate {
    private let html: String
    private let size: CGSize
    private let fullPage: Bool
    private let dark: Bool
    private let output: URL
    private var window: NSWindow?
    private var webView: WKWebView?

    init(html: String, size: CGSize, fullPage: Bool, dark: Bool, output: URL) {
        self.html = html
        self.size = size
        self.fullPage = fullPage
        self.dark = dark
        self.output = output
    }

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let frame = CGRect(origin: .zero, size: size)
        let web = WKWebView(frame: frame)
        web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        web.navigationDelegate = self
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = web.appearance
        window.contentView = web
        window.orderBack(nil)
        self.window = window
        self.webView = web
        web.loadHTMLString(html, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { CommandLineTool.fail("snapshot timed out") }
        app.run()
        exit(0)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard fullPage else { return capture() }
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [self] value, _ in
                let height = min(max((value as? Double) ?? size.height, size.height), 16000)
                window?.setContentSize(CGSize(width: size.width, height: height))
                webView.frame = CGRect(x: 0, y: 0, width: size.width, height: height)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.capture() }
            }
        }
    }

    private func capture() {
        guard let webView else { return }
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        config.afterScreenUpdates = true
        webView.takeSnapshot(with: config) { [self] image, error in
            guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                CommandLineTool.fail("snapshot failed: \(error?.localizedDescription ?? "no image")")
            }
            do { try png.write(to: output) } catch { CommandLineTool.fail("\(error)") }
            exit(0)
        }
    }
}

/// Test hook: loads a file into the system's Quick Look view (QLPreviewView), the same machinery
/// Finder's spacebar preview uses, in an off-screen window. Inspect it from outside with accessibility.
///
///   Lookdown --quicklook <file> [seconds]
final class QuickLookProbe: NSObject {
    private let file: URL
    private let seconds: Double
    private var window: NSWindow?

    init(file: URL, seconds: Double) {
        self.file = file
        self.seconds = seconds
    }

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // Borderless and far off-screen, so it never covers the user's work. (AppKit pulls titled
        // windows back onto the screen, which is why this one has no title bar.)
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 920, height: 1000),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        guard let view = QLPreviewView(frame: window.contentLayoutRect, style: .normal) else {
            CommandLineTool.fail("couldn't make a QLPreviewView")
        }
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        view.previewItem = file as NSURL
        window.orderFrontRegardless()
        self.window = window
        print("pid \(getpid())")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            window.close()
            exit(0)
        }
        app.run()
        exit(0)
    }
}
