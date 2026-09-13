// Harness testowy: ładuje edytor w WKWebView (ten sam silnik co aplikacja), uruchamia scenariusze z tests/webtest.js
// i zapisuje zrzuty. Użycie: webtest <katalog web> <plik testów js> <plik demo md> <katalog na zrzuty>
import AppKit
import UniformTypeIdentifiers
import WebKit

let args = CommandLine.arguments
let webRoot = URL(fileURLWithPath: args[1])
let testJS = try! String(contentsOfFile: args[2], encoding: .utf8)
let demo = try! String(contentsOfFile: args[3], encoding: .utf8)
let snapDir = URL(fileURLWithPath: args[4])

final class Scheme: NSObject, WKURLSchemeHandler {
    func webView(_ w: WKWebView, start t: WKURLSchemeTask) {
        let f = webRoot.appendingPathComponent(String(t.request.url!.path.dropFirst()))
        guard let d = try? Data(contentsOf: f) else { t.didFailWithError(URLError(.fileDoesNotExist)); return }
        let mime = UTType(filenameExtension: f.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        t.didReceive(HTTPURLResponse(url: t.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": mime])!)
        t.didReceive(d)
        t.didFinish()
    }
    func webView(_ w: WKWebView, stop t: WKURLSchemeTask) {}
}

final class Runner: NSObject, WKScriptMessageHandler {
    var web: WKWebView!
    var window: NSWindow!
    var changes = 0

    func start() {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(Scheme(), forURLScheme: "markedit")
        cfg.userContentController.add(self, name: "bridge")
        cfg.userContentController.addUserScript(WKUserScript(source: """
            window.__errors = [];
            addEventListener('error', e => __errors.push(String(e.message) + ' @' + e.lineno));
            addEventListener('unhandledrejection', e => __errors.push('rejection: ' + e.reason));
            document.addEventListener('securitypolicyviolation', e => __errors.push('CSP: ' + e.violatedDirective + ' ' + e.blockedURI));
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1300, height: 820), configuration: cfg)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = web
        window.setFrameOrigin(NSPoint(x: -4000, y: 0))
        window.orderFrontRegardless()
        window.makeKey()
        web.load(URLRequest(url: URL(string: "markedit://app/index.html")!))
    }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let b = m.body as? [String: Any], let type = b["type"] as? String else { return }
        if type == "change" { changes += 1 }
        if type == "ready" { Task { @MainActor in await self.run() } }
    }

    @MainActor func js(_ code: String, _ a: [String: Any] = [:]) async -> Any? {
        do { return try await web.callAsyncJavaScript(code, arguments: a, contentWorld: .page) }
        catch { return "JS EXCEPTION: \(error)" }
    }

    @MainActor func snap(_ name: String) async {
        let cfg = WKSnapshotConfiguration()
        if let img = try? await web.takeSnapshot(configuration: cfg),
           let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: snapDir.appendingPathComponent(name + ".png"))
        }
    }

    @MainActor func run() async {
        _ = await js("app.init(t, 'split', true)", ["t": demo])
        let loaded = await js(testJS)
        if let error = loaded as? String, error.hasPrefix("JS EXCEPTION") {
            print(error)
            exit(1)
        }
        let names = (await js("return Object.keys(window.tests)") as? [String]) ?? []
        guard !names.isEmpty else { print("FAIL: brak scenariuszy testowych"); exit(1) }
        var failed = 0
        for name in names {
            let r = await js("return await window.tests[n]()", ["n": name])
            let s = "\(r ?? "nil")"
            if s.hasPrefix("FAIL") || s.hasPrefix("JS EXCEPTION") { failed += 1 }
            print("[\(name)] \(s)")
            if name.hasPrefix("snap") { await snap(name) }
        }
        let errs = await js("return window.__errors.join('\\n')") as? String ?? "Nie udało się odczytać błędów JS"
        if !errs.isEmpty { failed += 1 }
        print("JS errors: \(errs.isEmpty ? "none" : errs)")
        print("bridge change messages: \(changes)")
        print(failed == 0 ? "ALL PASSED" : "\(failed) FAILED")
        exit(failed == 0 ? 0 : 1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let runner = Runner()
runner.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("TIMEOUT"); exit(2) }
app.run()
