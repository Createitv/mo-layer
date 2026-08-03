import Combine
import SwiftUI
import WebKit

@MainActor
final class BrowserViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKDownloadDelegate {
    @Published var urlString = "https://duckduckgo.com"
    @Published var title = L.string("Private Browser")
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var tabs: [BrowserTabState]
    @Published var selectedTabID: UUID

    let webView: WKWebView

    override init() {
        let initialTab = BrowserTabState(urlString: "https://duckduckgo.com")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.tabs = [initialTab]
        self.selectedTabID = initialTab.id
        super.init()
        webView.navigationDelegate = self
        loadCurrent()
    }

    func loadCurrent() {
        guard let url = URL(string: normalizedURLString(urlString)) else { return }
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }

    func addTab() {
        let tab = BrowserTabState(urlString: "https://duckduckgo.com")
        tabs.append(tab)
        selectedTabID = tab.id
        urlString = tab.urlString
        loadCurrent()
    }

    func closeSelectedTab() {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs.remove(at: index)
        let nextIndex = min(max(0, index - 1), tabs.count - 1)
        selectedTabID = tabs[nextIndex].id
        urlString = tabs[nextIndex].urlString
        loadCurrent()
    }

    func clearPrivateData() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.nonPersistent().removeData(ofTypes: types, modifiedSince: .distantPast) {}
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        title = webView.title ?? L.string("Private Browser")
        urlString = webView.url?.absoluteString ?? urlString
        if let index = tabs.firstIndex(where: { $0.id == selectedTabID }) {
            tabs[index].title = title
            tabs[index].urlString = urlString
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    nonisolated func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PrivateBrowserDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        return directory.appendingPathComponent(Self.sanitizedDownloadFilename(suggestedFilename), isDirectory: false)
    }

    func downloadDidFinish(_ download: WKDownload) {}

    nonisolated static func sanitizedDownloadFilename(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "\(UUID().uuidString).download"
        guard !trimmed.isEmpty else { return fallback }

        let lastComponent = URL(fileURLWithPath: trimmed).lastPathComponent
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
            .union(.controlCharacters)
        let sanitized = lastComponent
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))

        guard !sanitized.isEmpty, sanitized != "." && sanitized != ".." else {
            return fallback
        }
        return sanitized
    }

    private func normalizedURLString(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        if value.contains(".") && !value.contains(" ") {
            return "https://\(value)"
        }
        let query = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        return "https://duckduckgo.com/?q=\(query)"
    }
}

struct BrowserTabState: Identifiable, Hashable {
    let id = UUID()
    var title = L.string("New Tab")
    var urlString: String
}

struct PrivateWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
