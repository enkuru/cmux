import Foundation
import WebKit

/// Handles messages from the cmux diff HTML viewer for per-hunk git operations.
/// Registered as "cmuxDiff" on WKUserContentController.
/// JS calls: window.webkit.messageHandlers.cmuxDiff.postMessage({...})
final class CmuxDiffMessageHandler: NSObject, WKScriptMessageHandler {
    static let shared = CmuxDiffMessageHandler()

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let directory = body["directory"] as? String else { return }

        switch action {
        case "stageHunk":
            guard let patch = body["patch"] as? String else { return }
            applyPatch(patch, directory: directory, stage: true)
        case "revertHunk":
            guard let patch = body["patch"] as? String else { return }
            applyPatch(patch, directory: directory, stage: false)
        case "stageFile":
            guard let fileName = body["file"] as? String else { return }
            runGit(["add", "--", fileName], in: directory)
        case "revertFile":
            guard let fileName = body["file"] as? String,
                  let status = body["status"] as? String else { return }
            if status == "?" {
                runGit(["clean", "-f", "--", fileName], in: directory)
            } else {
                runGit(["checkout", "--", fileName], in: directory)
            }
        default:
            break
        }
    }

    private func applyPatch(_ patch: String, directory: String, stage: Bool) {
        let tempDir = FileManager.default.temporaryDirectory
        let patchFile = tempDir.appendingPathComponent("cmux-hunk-\(UUID().uuidString).patch")
        do {
            try patch.write(to: patchFile, atomically: true, encoding: .utf8)
            if stage {
                runGit(["apply", "--cached", patchFile.path], in: directory)
            } else {
                // Reverse-apply to revert
                runGit(["apply", "--reverse", patchFile.path], in: directory)
            }
            try? FileManager.default.removeItem(at: patchFile)
        } catch {}
    }

    @discardableResult
    private func runGit(_ args: [String], in directory: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = args
        task.currentDirectoryURL = URL(fileURLWithPath: directory)
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
