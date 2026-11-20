import AppKit
import Observation
import UniformTypeIdentifiers

let previewExtensionID = "com.zachburkhart.Lookdown.Preview"

/// Whether macOS has the Quick Look extension registered and switched on.
enum ExtensionState: Equatable {
    case checking, enabled, disabled, missing

    static func current() -> ExtensionState {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-i", previewExtensionID]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return .missing }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard let line = output.split(separator: "\n").first(where: { $0.contains(previewExtensionID) }) else {
            return .missing
        }
        // pluginkit prefixes "-" when the user has turned an extension off.
        return line.trimmingCharacters(in: .whitespaces).hasPrefix("-") ? .disabled : .enabled
    }
}

@Observable
final class AppModel {
    private(set) var settings: LookdownSettings
    private(set) var html = ""
    private(set) var previewFile: URL?
    private(set) var extensionState = ExtensionState.checking
    private(set) var saveError: String?

    let renderer: MarkdownRenderer
    private let sampleURL: URL

    static let markdownTypes: [UTType] = {
        var types: [UTType] = [UTType("net.daringfireball.markdown"), UTType("com.zachburkhart.lookdown.markdown")]
            .compactMap { $0 }
        types.append(.plainText)
        return types
    }()

    init() {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        renderer = MarkdownRenderer(resources: resources)
        sampleURL = resources.appendingPathComponent("sample.md")
        settings = SettingsStore.load()
        refresh()
        checkExtension()
    }

    func update(_ change: (inout LookdownSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        do {
            try SettingsStore.save(settings)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        let url = previewFile ?? sampleURL
        do {
            html = try renderer.page(for: url, settings: settings)
        } catch {
            html = "<!doctype html><p style=\"font: 14px -apple-system; padding: 2em\">Couldn't read " +
                MarkdownRenderer.escape(url.lastPathComponent) + ": " + MarkdownRenderer.escape(error.localizedDescription) + "</p>"
        }
    }

    func open(_ url: URL) {
        previewFile = url
        refresh()
    }

    func showSample() {
        previewFile = nil
        refresh()
    }

    func checkExtension() {
        DispatchQueue.global(qos: .userInitiated).async {
            let state = ExtensionState.current()
            DispatchQueue.main.async { self.extensionState = state }
        }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.markdownTypes
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Markdown file to preview"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
}
