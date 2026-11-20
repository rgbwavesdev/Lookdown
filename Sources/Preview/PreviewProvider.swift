import Cocoa
import OSLog
import QuickLookUI
import UniformTypeIdentifiers

private let log = Logger(subsystem: "com.zachburkhart.Lookdown", category: "preview")

/// The Quick Look extension: a data-based preview that hands Quick Look a finished HTML page.
@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let renderer = MarkdownRenderer(resources: Bundle.main.resourceURL ?? Bundle.main.bundleURL)

    func providePreview(for request: QLFilePreviewRequest,
                        completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void) {
        let fileURL = request.fileURL
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 920, height: 1040)) { _ in
            let started = Date()
            let settings = SettingsStore.load()
            do {
                let html = try Self.renderer.page(for: fileURL, settings: settings)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                log.info("Previewed \(fileURL.lastPathComponent, privacy: .public) with \(settings.theme.rawValue, privacy: .public) in \(ms) ms, \(html.utf8.count / 1024) KB")
                return Data(html.utf8)
            } catch {
                log.error("Couldn't preview \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
        reply.stringEncoding = .utf8
        handler(reply, nil)
    }
}
