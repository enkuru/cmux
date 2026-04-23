import Foundation
import WebKit

/// Opens a Monaco diff editor in a browser panel and handles approve/reject.
/// Bridges between the IDE MCP server's openDiff tool and the cmux UI.
enum IDEDiffEditorPanel {

    /// Open a diff editor panel for the given file.
    /// - Parameters:
    ///   - oldFilePath: Path to the original file
    ///   - newContent: Proposed new content
    ///   - tabName: Display name for the diff tab
    ///   - tabManager: TabManager to create the browser panel
    ///   - onResult: Called when user approves (with edited content) or rejects
    @MainActor
    static func open(
        oldFilePath: String,
        newContent: String,
        tabName: String,
        tabManager: TabManager,
        onResult: @escaping (IDEMCPServer.DiffResult) -> Void
    ) {
        let originalContent = (try? String(contentsOfFile: oldFilePath, encoding: .utf8)) ?? ""
        let fileName = (oldFilePath as NSString).lastPathComponent
        let language = detectLanguage(fileName)

        // Generate a unique ID for this diff session
        let sessionId = UUID().uuidString

        // Register the callback
        IDEDiffMessageHandler.shared.registerSession(id: sessionId, onResult: onResult)

        // Generate and write HTML
        let html = diffEditorHTML(
            originalContent: originalContent,
            proposedContent: newContent,
            fileName: fileName,
            language: language,
            sessionId: sessionId
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-ide-diffs", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let htmlFile = tempDir.appendingPathComponent("diff-\(sessionId).html")
        try? html.write(to: htmlFile, atomically: true, encoding: .utf8)

        // Open in browser panel
        tabManager.openBrowser(url: htmlFile)
    }

    private static func detectLanguage(_ fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "ts", "tsx": return "typescript"
        case "js", "jsx": return "javascript"
        case "py": return "python"
        case "rb": return "ruby"
        case "go": return "go"
        case "rs": return "rust"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "cs": return "csharp"
        case "html", "htm": return "html"
        case "css": return "css"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "xml": return "xml"
        case "sql": return "sql"
        case "sh", "bash", "zsh": return "shell"
        case "md", "markdown": return "markdown"
        case "zig": return "zig"
        default: return "plaintext"
        }
    }

    private static func escapeForJS(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "`", with: "\\`")
           .replacingOccurrences(of: "$", with: "\\$")
           .replacingOccurrences(of: "</", with: "<\\/")
    }

    private static func diffEditorHTML(
        originalContent: String,
        proposedContent: String,
        fileName: String,
        language: String,
        sessionId: String
    ) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    background: #1e1e1e; color: #cccccc;
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
                    display: flex; flex-direction: column; height: 100vh; overflow: hidden;
                }
                .toolbar {
                    display: flex; align-items: center; justify-content: space-between;
                    padding: 8px 16px; background: #252526; border-bottom: 1px solid #3c3c3c;
                    flex-shrink: 0;
                }
                .toolbar-left { display: flex; align-items: center; gap: 12px; }
                .toolbar-right { display: flex; align-items: center; gap: 8px; }
                .file-name { font-size: 12px; font-weight: 600; color: #e0e0e0; }
                .view-toggle {
                    display: flex; background: #3c3c3c; border-radius: 4px; overflow: hidden;
                }
                .view-toggle button {
                    padding: 4px 10px; font-size: 11px; font-weight: 500;
                    border: none; cursor: pointer; color: #aaa;
                    background: transparent; transition: all 0.15s;
                }
                .view-toggle button.active { background: #0078d4; color: white; }
                .view-toggle button:hover:not(.active) { background: #4c4c4c; color: #ddd; }
                .btn {
                    padding: 5px 14px; font-size: 12px; font-weight: 600;
                    border: none; border-radius: 4px; cursor: pointer; transition: all 0.15s;
                }
                .btn-approve { background: #28a745; color: white; }
                .btn-approve:hover { background: #2ea44f; }
                .btn-reject { background: #dc3545; color: white; }
                .btn-reject:hover { background: #e3505f; }
                .btn-approve:active, .btn-reject:active { transform: scale(0.97); }
                #editor-container { flex: 1; overflow: hidden; }
                /* Hide original line numbers in unified/inline mode */
                #editor-container .editor.modified .margin-view-overlays .line-numbers { display: none; }
                .diff-hidden-lines { display: none !important; }
                .kbd {
                    font-size: 10px; color: #888; background: #333;
                    padding: 1px 5px; border-radius: 3px; margin-left: 4px;
                }
            </style>
        </head>
        <body>
            <div class="toolbar">
                <div class="toolbar-left">
                    <span class="file-name">\(escapeForJS(fileName))</span>
                    <div class="view-toggle">
                        <button id="btn-split" class="active" onclick="setView('split')">Split</button>
                        <button id="btn-unified" onclick="setView('unified')">Unified</button>
                    </div>
                </div>
                <div class="toolbar-right">
                    <button class="btn btn-reject" id="btn-reject">Reject <span class="kbd">Esc</span></button>
                    <button class="btn btn-approve" id="btn-approve">Approve <span class="kbd">\u{2318}S</span></button>
                </div>
            </div>
            <div id="debug-bar" style="background:#333;color:#0f0;font-size:10px;padding:2px 8px;font-family:monospace;display:none;"></div>
            <div id="editor-container"></div>
            <script src="https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs/loader.js"></script>
            <script>
                const originalContent = `\(escapeForJS(originalContent))`;
                const proposedContent = `\(escapeForJS(proposedContent))`;
                const language = '\(language)';
                const sessionId = '\(sessionId)';

                let diffEditor = null;
                let settled = false;

                require.config({ paths: { vs: 'https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs' } });
                require(['vs/editor/editor.main'], function () {
                    monaco.editor.defineTheme('cmuxDark', {
                        base: 'vs-dark', inherit: true, rules: [],
                        colors: {
                            'editor.background': '#1e1e1e',
                            'diffEditor.insertedTextBackground': '#28a74520',
                            'diffEditor.removedTextBackground': '#dc354520',
                        }
                    });
                    monaco.editor.setTheme('cmuxDark');
                    createEditor(false);
                });

                function createEditor(inline) {
                    const container = document.getElementById('editor-container');
                    const currentContent = diffEditor
                        ? diffEditor.getModifiedEditor().getValue()
                        : proposedContent;
                    container.innerHTML = '';
                    diffEditor = monaco.editor.createDiffEditor(container, {
                        theme: 'cmuxDark', automaticLayout: true,
                        renderSideBySide: !inline, readOnly: false, originalEditable: false,
                        fontSize: 13,
                        fontFamily: "'SF Mono', Menlo, Monaco, 'Courier New', monospace",
                        minimap: { enabled: false }, scrollBeyondLastLine: false,
                        renderOverviewRuler: false, diffWordWrap: 'on',
                    });
                    diffEditor.setModel({
                        original: monaco.editor.createModel(originalContent, language),
                        modified: monaco.editor.createModel(currentContent, language),
                    });
                }

                function setView(view) {
                    document.getElementById('btn-split').classList.toggle('active', view === 'split');
                    document.getElementById('btn-unified').classList.toggle('active', view === 'unified');
                    createEditor(view === 'unified');
                }

                function dbg(msg) {
                    const bar = document.getElementById('debug-bar');
                    bar.style.display = 'block';
                    bar.textContent = msg;
                }

                function doApprove() {
                    if (settled) return;
                    settled = true;
                    const content = diffEditor.getModifiedEditor().getValue();
                    window.webkit.messageHandlers.cmuxIDEDiff.postMessage({
                        action: 'approve',
                        sessionId: sessionId,
                        content: content
                    });
                }

                function doReject() {
                    if (settled) return;
                    settled = true;
                    window.webkit.messageHandlers.cmuxIDEDiff.postMessage({
                        action: 'reject',
                        sessionId: sessionId
                    });
                }

                document.getElementById('btn-approve').addEventListener('click', function(e) {
                    e.stopPropagation();
                    doApprove();
                });
                document.getElementById('btn-reject').addEventListener('click', function(e) {
                    e.stopPropagation();
                    doReject();
                });
                document.addEventListener('keydown', function(e) {
                    if (e.key === 'Escape') { e.preventDefault(); doReject(); }
                    if ((e.metaKey || e.ctrlKey) && e.key === 's') { e.preventDefault(); doApprove(); }
                });
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - Message Handler

/// Handles approve/reject messages from the Monaco diff editor browser panel.
final class IDEDiffMessageHandler: NSObject, WKScriptMessageHandler {
    static let shared = IDEDiffMessageHandler()

    private var sessions: [String: (IDEMCPServer.DiffResult) -> Void] = [:]
    private let lock = NSLock()

    func registerSession(id: String, onResult: @escaping (IDEMCPServer.DiffResult) -> Void) {
        lock.lock()
        sessions[id] = onResult
        NSLog("[cmux-ide-diff] registerSession: %@, total=%d", id, sessions.count)
        lock.unlock()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        processMessage(body)
    }

    /// Handle messages received via document.title change fallback.
    func handleTitleMessage(_ json: String) {
        guard let data = json.data(using: .utf8),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        processMessage(body)
    }

    private func processMessage(_ body: [String: Any]) {
        guard let action = body["action"] as? String,
              let sessionId = body["sessionId"] as? String else {
            NSLog("[cmux-ide-diff] processMessage: missing action or sessionId in %@", "\(body)")
            return
        }

        lock.lock()
        let sessionCount = sessions.count
        let callback = sessions.removeValue(forKey: sessionId)
        lock.unlock()

        NSLog("[cmux-ide-diff] processMessage: action=%@, sessionId=%@, sessionsCount=%d, callbackFound=%d",
              action, sessionId, sessionCount, callback != nil ? 1 : 0)

        switch action {
        case "approve":
            let content = body["content"] as? String ?? ""
            callback?(.accepted(content: content))
        case "reject":
            callback?(.rejected)
        default:
            break
        }
    }
}
