import AppKit
import SwiftUI
import WebKit

/// Shows a rendered page and keeps the scroll position when the page is re-rendered.
struct WebPreview: NSViewRepresentable {
    var html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.allowsMagnification = true
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.html != html else { return }
        let first = coordinator.html == nil
        coordinator.html = html
        if first {
            view.loadHTMLString(html, baseURL: nil)
            return
        }
        view.evaluateJavaScript("window.scrollY") { value, _ in
            coordinator.restoreY = value as? Double
            view.loadHTMLString(coordinator.html ?? "", baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var html: String?
        var restoreY: Double?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let y = restoreY, y > 0 else { return }
            restoreY = nil
            webView.evaluateJavaScript("window.scrollTo(0, \(y))")
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                decisionHandler(.allow)
                return
            }
            // In-page links (footnotes, #headings) stay here; everything else opens normally.
            if url.scheme == "about" || (url.fragment != nil && url.absoluteString.hasPrefix("about:")) {
                decisionHandler(.allow)
                return
            }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}
