import Foundation
import Network
import CryptoKit

/// MCP-compatible WebSocket server that integrates with Claude Code's IDE protocol.
/// Claude Code auto-discovers this server via lock files in ~/.claude/ide/.
/// Implements the openDiff tool to show diffs in cmux's internal Monaco diff editor.
final class IDEMCPServer {
    static let shared = IDEMCPServer()

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: IDEMCPConnection] = [:]
    private let queue = DispatchQueue(label: "com.cmux.ide-mcp-server", qos: .userInitiated)
    private let authToken: String
    private var port: UInt16 = 0
    private var lockFilePath: String?

    /// Callback to open a diff panel in the UI. Set by AppDelegate.
    var openDiffHandler: ((_ oldPath: String, _ newPath: String, _ newContent: String, _ tabName: String, _ onResult: @escaping (DiffResult) -> Void) -> Void)?

    /// Called when a pending diff should be dismissed (connection closed, new diff opened, etc.)
    var dismissActiveDiffHandler: (() -> Void)?

    /// The connection that owns the active diff — only dismiss when THIS connection closes.
    private var activeDiffConnectionId: ObjectIdentifier?

    /// Callback to open a file in the UI.
    var openFileHandler: ((_ filePath: String, _ startLine: Int?, _ endLine: Int?) -> Void)?

    /// Callback to get workspace folders.
    var getWorkspaceFoldersHandler: (() -> [String])?

    enum DiffResult {
        case accepted(content: String)
        case rejected
    }

    private init() {
        // Generate a cryptographically secure auth token
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        self.authToken = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            self?.startServer()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopServer()
        }
    }

    private func startServer() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)

        let wsOptions = NWProtocolWebSocket.Options(.version13)
        wsOptions.autoReplyPing = true
        // Validate auth after connection instead of during handshake,
        // since the NWProtocolWebSocket server-side API is limited.
        // We'll check auth in the first message received.
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: params)
        } catch {
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port?.rawValue {
                    self?.port = port
                    self?.writeLockFile()
                }
            case .failed:
                self?.stopServer()
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
    }

    private func stopServer() {
        removeLockFile()
        for (_, conn) in connections {
            conn.close()
        }
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }

    // MARK: - Lock File

    private func writeLockFile() {
        let ideDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/ide")
        try? FileManager.default.createDirectory(at: ideDir, withIntermediateDirectories: true)

        let workspaceFolders = DispatchQueue.main.sync {
            getWorkspaceFoldersHandler?() ?? []
        }

        let lockData: [String: Any] = [
            "workspaceFolders": workspaceFolders,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "ideName": "cmux",
            "transport": "ws",
            "authToken": authToken,
        ]

        let path = ideDir.appendingPathComponent("\(port).lock")
        lockFilePath = path.path

        if let data = try? JSONSerialization.data(withJSONObject: lockData, options: .prettyPrinted) {
            try? data.write(to: path)
        }
    }

    private func removeLockFile() {
        if let path = lockFilePath {
            try? FileManager.default.removeItem(atPath: path)
            lockFilePath = nil
        }
    }

    /// Update workspace folders in the lock file (call when tabs change).
    func updateWorkspaceFolders() {
        guard lockFilePath != nil else { return }
        queue.async { [weak self] in
            self?.writeLockFile()
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let conn = IDEMCPConnection(connection: nwConnection, server: self)
        connections[ObjectIdentifier(nwConnection)] = conn
        conn.start(on: queue)
    }

    func connectionClosed(_ nwConnection: NWConnection) {
        let connId = ObjectIdentifier(nwConnection)
        queue.async { [weak self] in
            self?.connections.removeValue(forKey: connId)
        }
        // Only dismiss the diff if it belongs to this connection
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activeDiffConnectionId == connId else { return }
            self.activeDiffConnectionId = nil
            self.dismissActiveDiffHandler?()
        }
    }

    // MARK: - Message Dispatch

    func handleMessage(_ message: [String: Any], from connection: IDEMCPConnection) {
        guard let method = message["method"] as? String else {
            // It's a response, not a request — ignore for now
            return
        }
        let id = message["id"] // Can be String, Int, or nil (notification)
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let result: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": ["listChanged": true],
                ],
                "serverInfo": [
                    "name": "cmux",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                ],
            ]
            connection.sendResult(id: id, result: result)

        case "notifications/initialized":
            break // No response needed

        case "tools/list":
            connection.sendResult(id: id, result: ["tools": toolDefinitions()])

        case "tools/call":
            handleToolCall(params: params, id: id, connection: connection)

        default:
            connection.sendError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Tools

    private func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "openDiff",
                "description": "Open a diff view comparing old file content with new file content",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "old_file_path": ["type": "string"],
                        "new_file_path": ["type": "string"],
                        "new_file_contents": ["type": "string"],
                        "tab_name": ["type": "string"],
                    ],
                    "required": ["old_file_path", "new_file_path", "new_file_contents", "tab_name"],
                ] as [String: Any],
            ],
            [
                "name": "openFile",
                "description": "Open a file in the editor",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "filePath": ["type": "string"],
                        "startLine": ["type": "integer"],
                        "endLine": ["type": "integer"],
                    ],
                    "required": ["filePath"],
                ] as [String: Any],
            ],
            [
                "name": "getDiagnostics",
                "description": "Get diagnostics for open files",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "uri": ["type": "string"],
                    ],
                ] as [String: Any],
            ],
            [
                "name": "saveDocument",
                "description": "Save a file",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "filePath": ["type": "string"],
                    ],
                    "required": ["filePath"],
                ] as [String: Any],
            ],
            [
                "name": "getWorkspaceFolders",
                "description": "Get workspace folders",
                "inputSchema": ["type": "object", "properties": [:] as [String: Any]] as [String: Any],
            ],
            [
                "name": "getOpenEditors",
                "description": "Get open editor tabs",
                "inputSchema": ["type": "object", "properties": [:] as [String: Any]] as [String: Any],
            ],
            [
                "name": "getCurrentSelection",
                "description": "Get current text selection",
                "inputSchema": ["type": "object", "properties": [:] as [String: Any]] as [String: Any],
            ],
            [
                "name": "getLatestSelection",
                "description": "Get latest text selection",
                "inputSchema": ["type": "object", "properties": [:] as [String: Any]] as [String: Any],
            ],
            [
                "name": "closeAllDiffTabs",
                "description": "Close all open diff tabs",
                "inputSchema": ["type": "object", "properties": [:] as [String: Any]] as [String: Any],
            ],
            [
                "name": "close_tab",
                "description": "Close a specific tab",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "tab_name": ["type": "string"],
                    ],
                    "required": ["tab_name"],
                ] as [String: Any],
            ],
            [
                "name": "checkDocumentDirty",
                "description": "Check if a document has unsaved changes",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "filePath": ["type": "string"],
                    ],
                    "required": ["filePath"],
                ] as [String: Any],
            ],
        ]
    }

    private func handleToolCall(params: [String: Any], id: Any?, connection: IDEMCPConnection) {
        guard let name = params["name"] as? String else {
            connection.sendError(id: id, code: -32602, message: "Missing tool name")
            return
        }
        let args = params["arguments"] as? [String: Any] ?? [:]

        switch name {
        case "openDiff":
            handleOpenDiff(args: args, id: id, connection: connection)
        case "openFile":
            handleOpenFile(args: args, id: id, connection: connection)
        case "getDiagnostics":
            connection.sendResult(id: id, result: ["content": [["type": "text", "text": "[]"]]])
        case "saveDocument":
            connection.sendResult(id: id, result: ["content": [["type": "text", "text": "OK"]]])
        case "getWorkspaceFolders":
            let folders = DispatchQueue.main.sync { getWorkspaceFoldersHandler?() ?? [] }
            let json = (try? JSONSerialization.data(withJSONObject: folders)) ?? Data()
            connection.sendResult(id: id, result: ["content": [["type": "text", "text": String(data: json, encoding: .utf8) ?? "[]"]]])
        case "getOpenEditors":
            connection.sendResult(id: id, result: ["content": [["type": "text", "text": "[]"]]])
        case "getCurrentSelection", "getLatestSelection":
            connection.sendResult(id: id, result: ["content": [["type": "text", "text": ""]]])
        case "closeAllDiffTabs", "close_tab":
            DispatchQueue.main.async { [weak self] in
                self?.dismissActiveDiffHandler?()
            }
            connection.sendResult(id: id, result: ["content": [["type": "text", "text": "OK"]]])
        case "checkDocumentDirty":
            connection.sendResult(id: id, result: ["content": [["type": "text", "text": "false"]]])
        default:
            connection.sendError(id: id, code: -32601, message: "Unknown tool: \(name)")
        }
    }

    // MARK: - openDiff (blocking)

    private func handleOpenDiff(args: [String: Any], id: Any?, connection: IDEMCPConnection) {
        guard let oldPath = args["old_file_path"] as? String,
              let newPath = args["new_file_path"] as? String,
              let newContent = args["new_file_contents"] as? String,
              let tabName = args["tab_name"] as? String else {
            connection.sendError(id: id, code: -32602, message: "Missing required openDiff parameters")
            return
        }

        // Open diff panel on main thread; response is deferred until user acts
        DispatchQueue.main.async { [weak self] in
            guard let self, let handler = self.openDiffHandler else {
                connection.sendResult(id: id, result: [
                    "content": [["type": "text", "text": "DIFF_REJECTED"], ["type": "text", "text": tabName]],
                ])
                return
            }

            // Track which connection owns this diff
            self.activeDiffConnectionId = connection.connectionId

            handler(oldPath, newPath, newContent, tabName) { [weak self] result in
                // Diff resolved (user accepted/rejected) — clear ownership
                self?.activeDiffConnectionId = nil

                switch result {
                case .accepted(let content):
                    connection.sendResult(id: id, result: [
                        "content": [["type": "text", "text": "FILE_SAVED"], ["type": "text", "text": content]],
                    ])
                case .rejected:
                    connection.sendResult(id: id, result: [
                        "content": [["type": "text", "text": "DIFF_REJECTED"], ["type": "text", "text": tabName]],
                    ])
                }
            }
        }
    }

    // MARK: - openFile

    private func handleOpenFile(args: [String: Any], id: Any?, connection: IDEMCPConnection) {
        guard let filePath = args["filePath"] as? String else {
            connection.sendError(id: id, code: -32602, message: "Missing filePath")
            return
        }
        let startLine = args["startLine"] as? Int
        let endLine = args["endLine"] as? Int

        DispatchQueue.main.async { [weak self] in
            self?.openFileHandler?(filePath, startLine, endLine)
        }
        connection.sendResult(id: id, result: ["content": [["type": "text", "text": "OK"]]])
    }
}

// MARK: - WebSocket Connection

final class IDEMCPConnection {
    private let connection: NWConnection
    private weak var server: IDEMCPServer?
    let connectionId: ObjectIdentifier

    init(connection: NWConnection, server: IDEMCPServer) {
        self.connection = connection
        self.server = server
        self.connectionId = ObjectIdentifier(connection)
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveMessage()
            case .failed, .cancelled:
                self?.server?.connectionClosed(self!.connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func close() {
        connection.cancel()
    }

    private func receiveMessage() {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self, error == nil, let data = content else {
                self?.server?.connectionClosed(self!.connection)
                return
            }

            if let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.server?.handleMessage(message, from: self)
            }

            // Continue receiving
            self.receiveMessage()
        }
    }

    func sendResult(id: Any?, result: Any) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result,
        ]
        sendJSON(response)
    }

    func sendError(id: Any?, code: Int, message: String) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": ["code": code, "message": message],
        ]
        sendJSON(response)
    }

    private func sendJSON(_ obj: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])

        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }
}
