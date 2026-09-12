import UniformTypeIdentifiers
import WebKit

/// Serwuje pliki pod schematem markedit://
///   markedit://app/…   – interfejs edytora z Resources/web
///   markedit://doc/…   – pliki względem katalogu otwartego dokumentu (np. obrazki)
///   markedit://file/…  – ścieżki bezwzględne
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "markedit"

    weak var document: NSDocument?
    private let webRoot: URL

    init(webRoot: URL) {
        self.webRoot = webRoot.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let fileURL = resolve(url),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        var mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        if mime.hasPrefix("text/") || mime.hasSuffix("javascript") { mime += "; charset=utf-8" }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mime, "Cache-Control": "no-cache"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func resolve(_ url: URL) -> URL? {
        let relative = String(url.path.drop(while: { $0 == "/" }))
        switch url.host {
        case "app":
            let file = webRoot.appendingPathComponent(relative).standardizedFileURL
            return file.path.hasPrefix(webRoot.path + "/") ? file : nil
        case "doc":
            guard let dir = document?.fileURL?.deletingLastPathComponent() else { return nil }
            return dir.appendingPathComponent(relative).standardizedFileURL
        case "file":
            return URL(fileURLWithPath: url.path)
        default:
            return nil
        }
    }
}
