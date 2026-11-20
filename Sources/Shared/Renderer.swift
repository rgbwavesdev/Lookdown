import Foundation
import ImageIO
import JavaScriptCore
import UniformTypeIdentifiers

/// Turns Markdown into one self-contained HTML page: styles, images and math fonts are inlined,
/// because Quick Look's web view can't load files next to the page. Shared by the Quick Look
/// extension, the app's live preview and the command line.
final class MarkdownRenderer {
    enum Scheme { case auto, light, dark }

    static let maxSourceBytes = 8 << 20
    static let maxImageBytes = 25 << 20
    static let imageBudget = 80 << 20

    let resources: URL

    private let lock = NSLock()
    private var context: JSContext?
    private var lookdown: JSValue?
    private var documentDirectory: URL?
    private var imageBytesLeft = 0
    private var baseCSS: String?
    private var themeSections: [String: String]?
    private var katexCSS: String?
    private var vaultRoots: [URL: URL?] = [:]
    private var fileIndex: (root: URL, built: Date, files: [String: URL])?

    init(resources: URL) {
        self.resources = resources
    }

    // MARK: Pages

    func page(for fileURL: URL, settings: LookdownSettings, scheme: Scheme? = nil) throws -> String {
        var data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        var notice: String?
        if data.count > Self.maxSourceBytes {
            let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            data = data.prefix(Self.maxSourceBytes)
            if let lastNewline = data.lastIndex(of: 0x0A) { data = data.prefix(upTo: lastNewline) }
            notice = "This file is \(size). The preview shows the first 8 MB."
        }
        return page(markdown: Self.decode(data), documentURL: fileURL, settings: settings,
                    title: fileURL.lastPathComponent, scheme: scheme, notice: notice)
    }

    func page(markdown: String, documentURL: URL?, settings: LookdownSettings, title: String,
              scheme: Scheme? = nil, notice: String? = nil) -> String {
        lock.lock()
        defer { lock.unlock() }

        documentDirectory = documentURL?.deletingLastPathComponent()
        imageBytesLeft = Self.imageBudget
        let (body, hasMath) = renderBody(markdown, settings: settings)
        documentDirectory = nil

        let resolved = scheme ?? {
            switch settings.appearance {
            case .system: return .auto
            case .light: return .light
            case .dark: return .dark
            }
        }()

        let images = settings.remoteImages ? "data: https: http:" : "data:"
        let csp = "default-src 'none'; img-src \(images); media-src \(images); style-src 'unsafe-inline'; font-src data:"
        let fontSize = String(format: "%.1f", settings.clampedFontSize)

        var html = """
        <!doctype html>
        <html lang="en" data-theme="\(settings.theme.rawValue)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta name="color-scheme" content="\(resolved == .light ? "light" : resolved == .dark ? "dark" : "light dark")">
        <title>\(Self.escape(title))</title>
        <style>
        \(stylesheet(theme: settings.theme, scheme: resolved))
        :root { --font-size: \(fontSize)px; --content-width: \(settings.width.css); }
        </style>

        """
        if hasMath { html += "<style>\n\(katexStylesheet())\n</style>\n" }
        html += "</head>\n<body>\n<article class=\"markdown-body\">\n"
        if let notice { html += "<div class=\"lookdown-notice\">\(Self.escape(notice))</div>\n" }
        html += body
        html += "</article>\n</body>\n</html>\n"
        return html
    }

    // MARK: Markdown

    private func renderBody(_ markdown: String, settings: LookdownSettings) -> (String, Bool) {
        if let engine = engine(),
           let result = engine.invokeMethod("render", withArguments: [markdown, settings.rendererOptions]),
           result.isObject,
           let html = result.forProperty("html"), html.isString {
            return (html.toString(), result.forProperty("math")?.toBool() ?? false)
        }
        return ("<pre class=\"lookdown-fallback\">\(Self.escape(markdown))</pre>", false)
    }

    private func engine() -> JSValue? {
        if let lookdown { return lookdown }
        guard let context = JSContext() else { return nil }
        context.name = "Lookdown"
        context.exceptionHandler = { _, exception in
            NSLog("Lookdown JS error: %@", exception?.toString() ?? "unknown")
        }
        context.evaluateScript("var console = { log() {}, info() {}, warn() {}, error() {}, debug() {} };")
        let resolve: @convention(block) (String, Bool) -> String = { [unowned self] src, wiki in
            self.imageSource(for: src, wiki: wiki)
        }
        context.setObject(resolve, forKeyedSubscript: "__lookdownResolve" as NSString)

        var scripts = ["vendor/markdown-it.min.js", "vendor/markdown-it-footnote.min.js",
                       "vendor/markdown-it-mark.min.js", "vendor/highlight.min.js"]
        let extras = resources.appendingPathComponent("vendor/hljs-extra")
        let extraFiles = (try? FileManager.default.contentsOfDirectory(atPath: extras.path)) ?? []
        scripts += extraFiles.filter { $0.hasSuffix(".js") }.sorted().map { "vendor/hljs-extra/\($0)" }
        scripts += ["vendor/katex.min.js", "lookdown.js"]

        for path in scripts {
            let url = resources.appendingPathComponent(path)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                NSLog("Lookdown: missing resource %@", path)
                continue
            }
            context.evaluateScript(source, withSourceURL: url)
        }
        let lookdown = context.objectForKeyedSubscript("Lookdown")
        guard let lookdown, lookdown.isObject else { return nil }
        self.context = context
        self.lookdown = lookdown
        return lookdown
    }

    // MARK: Styles

    private func text(_ path: String) -> String {
        (try? String(contentsOf: resources.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    private func stylesheet(theme: LookdownSettings.Theme, scheme: Scheme) -> String {
        if baseCSS == nil { baseCSS = text("lookdown.css") }
        if themeSections == nil { themeSections = Self.sections(of: text("themes.css")) }
        let sections = themeSections ?? [:]
        let base = sections["\(theme.rawValue) base"] ?? ""
        let light = sections["\(theme.rawValue) light"] ?? ""
        let dark = sections["\(theme.rawValue) dark"] ?? ""
        var css = (baseCSS ?? "") + "\n" + base + "\n"
        switch scheme {
        case .light: css += light
        case .dark: css += dark
        case .auto: css += light + "\n@media (prefers-color-scheme: dark) {\n" + dark + "\n}\n"
        }
        return css
    }

    /// Splits themes.css at its "/*@ name part */" markers.
    private static func sections(of css: String) -> [String: String] {
        guard let marker = try? NSRegularExpression(pattern: #"/\*@\s*(\w+)\s+(\w+)\s*\*/"#) else { return [:] }
        let ns = css as NSString
        let matches = marker.matches(in: css, range: NSRange(location: 0, length: ns.length))
        var out: [String: String] = [:]
        for (i, m) in matches.enumerated() {
            let start = m.range.location + m.range.length
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let key = ns.substring(with: m.range(at: 1)) + " " + ns.substring(with: m.range(at: 2))
            out[key] = ns.substring(with: NSRange(location: start, length: end - start))
        }
        return out
    }

    /// KaTeX's stylesheet with its fonts embedded as woff2 data URIs.
    private func katexStylesheet() -> String {
        if let katexCSS { return katexCSS }
        var css = text("vendor/katex.min.css")
        let pattern = #"src:url\(fonts/([A-Za-z0-9_-]+)\.woff2\) format\("woff2"\)(?:,url\([^)]*\) format\("[^"]*"\))*"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = css as NSString
            var result = ""
            var cursor = 0
            for m in regex.matches(in: css, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                let name = ns.substring(with: m.range(at: 1))
                let font = resources.appendingPathComponent("vendor/katex-fonts/\(name).woff2")
                if let data = try? Data(contentsOf: font) {
                    result += "src:url(data:font/woff2;base64,\(data.base64EncodedString())) format(\"woff2\")"
                } else {
                    result += ns.substring(with: m.range)
                }
                cursor = m.range.location + m.range.length
            }
            result += ns.substring(from: cursor)
            css = result
        }
        katexCSS = css
        return css
    }

    // MARK: Images

    /// Called from JavaScript for each local image. Returns a data: URI, or "" if the image
    /// can't be found or is too large.
    private func imageSource(for raw: String, wiki: Bool) -> String {
        guard let directory = documentDirectory else { return "" }
        var src = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return "" }

        var candidates: [URL] = []
        if src.lowercased().hasPrefix("file:") {
            if let url = URL(string: src), url.isFileURL { candidates.append(url) }
        } else {
            if !wiki, let cut = src.firstIndex(where: { $0 == "?" || $0 == "#" }) {
                src = String(src[..<cut])
            }
            let path = src.removingPercentEncoding ?? src
            if path.hasPrefix("/") {
                candidates.append(URL(fileURLWithPath: path))
            } else if path.hasPrefix("~/") {
                candidates.append(SettingsStore.realHome.appendingPathComponent(String(path.dropFirst(2))))
            } else {
                candidates.append(directory.appendingPathComponent(path))
                if let vault = vaultRoot(for: directory) {
                    candidates.append(vault.appendingPathComponent(path))
                }
            }
        }

        let fm = FileManager.default
        var found = candidates.map(\.standardizedFileURL).first { fm.fileExists(atPath: $0.path) }
        if found == nil, let name = candidates.first?.lastPathComponent, !name.isEmpty {
            found = search(named: name, near: directory)
        }
        guard let url = found else { return "" }
        return dataURI(for: url)
    }

    private func dataURI(for url: URL) -> String {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= Self.maxImageBytes, size <= imageBytesLeft,
              var data = try? Data(contentsOf: url, options: .mappedIfSafe)
        else { return "" }

        var mime = Self.mimeType(extension: url.pathExtension, data: data)
        // WebKit doesn't reliably draw HEIC or TIFF inside Quick Look, so convert those.
        if mime == "image/heic" || mime == "image/tiff" {
            guard let converted = Self.transcode(data, to: mime == "image/heic" ? .jpeg : .png) else { return "" }
            data = converted
            mime = mime == "image/heic" ? "image/jpeg" : "image/png"
        }
        guard let mime else { return "" }
        imageBytesLeft -= data.count
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private static func mimeType(extension ext: String, data: Data) -> String? {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "bmp": return "image/bmp"
        case "avif": return "image/avif"
        case "ico": return "image/x-icon"
        case "heic", "heif": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        default: break
        }
        let head = [UInt8](data.prefix(16))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if head.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if head.count >= 12, head.starts(with: [0x52, 0x49, 0x46, 0x46]), Array(head[8..<12]) == [0x57, 0x45, 0x42, 0x50] {
            return "image/webp"
        }
        let start = String(decoding: data.prefix(256), as: UTF8.self).lowercased()
        if start.contains("<svg") { return "image/svg+xml" }
        return nil
    }

    private static func transcode(_ data: Data, to type: UTType) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        let orientation = (props as? [CFString: Any])?[kCGImagePropertyOrientation]
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.88]
        if let orientation { options[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// The Obsidian vault that holds `directory` (the nearest folder with a .obsidian folder).
    private func vaultRoot(for directory: URL) -> URL? {
        if let cached = vaultRoots[directory] { return cached }
        var found: URL?
        var dir = directory.standardizedFileURL
        let home = SettingsStore.realHome.standardizedFileURL.path
        for _ in 0..<16 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".obsidian").path) {
                found = dir
                break
            }
            if dir.path == "/" || dir.path == home { break }
            dir = dir.deletingLastPathComponent()
        }
        vaultRoots[directory] = .some(found)
        return found
    }

    /// Finds an attachment by file name: anywhere in the vault, or within a few folders of the
    /// document when it isn't in a vault.
    private func search(named name: String, near directory: URL) -> URL? {
        let vault = vaultRoot(for: directory)
        let root = (vault ?? directory).standardizedFileURL
        // Never crawl the whole home folder: that would reach Desktop, Documents and the like.
        if root.path == "/" || root.path == SettingsStore.realHome.standardizedFileURL.path { return nil }
        let key = name.lowercased()
        if let index = fileIndex, index.root == root, Date().timeIntervalSince(index.built) < 30 {
            return index.files[key]
        }
        var files: [String: URL] = [:]
        let maxDepth = vault == nil ? 3 : 12
        let baseDepth = root.pathComponents.count
        let started = Date()
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            var seen = 0
            for case let url as URL in walker {
                seen += 1
                if seen > 40_000 || (seen % 500 == 0 && Date().timeIntervalSince(started) > 1.5) { break }
                if url.pathComponents.count - baseDepth > maxDepth {
                    walker.skipDescendants()
                    continue
                }
                let lower = url.lastPathComponent.lowercased()
                if files[lower] == nil { files[lower] = url }
            }
        }
        fileIndex = (root, Date(), files)
        return files[key]
    }

    // MARK: Text

    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .utf8) { return text }
        let lossy = String(decoding: data, as: UTF8.self)
        var bad = 0
        for scalar in lossy.unicodeScalars where scalar == "\u{FFFD}" {
            bad += 1
            if bad > 8 { break }
        }
        if bad <= 8 { return lossy }
        return String(data: data, encoding: .windowsCP1252) ?? lossy
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
