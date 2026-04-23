import Foundation
import SwiftUI

/// Groups workspaces by their common project directory for sidebar display.
@MainActor
final class ProjectGrouping: ObservableObject {

    struct ProjectGroup: Identifiable {
        let id: String  // normalized directory path
        let name: String  // folder name (e.g., "pos-api")
        let directory: String  // full path
        var workspaceIds: [UUID]
        var worktreeCount: Int  // number of .worktrees/ entries
    }

    @Published var groups: [ProjectGroup] = []
    @Published var ungroupedIds: [UUID] = []  // workspaces with unique directories

    /// Persisted collapsed state per project path
    @AppStorage("projectGroupCollapsedPaths") private var collapsedPathsRaw: String = ""

    var collapsedPaths: Set<String> {
        get { Set(collapsedPathsRaw.split(separator: "\n").map(String.init)) }
        set { collapsedPathsRaw = newValue.sorted().joined(separator: "\n") }
    }

    func isCollapsed(_ projectPath: String) -> Bool {
        collapsedPaths.contains(projectPath)
    }

    func toggleCollapsed(_ projectPath: String) {
        objectWillChange.send()
        var paths = collapsedPaths
        if paths.contains(projectPath) {
            paths.remove(projectPath)
        } else {
            paths.insert(projectPath)
        }
        collapsedPaths = paths
    }

    // MARK: - Worktree Info

    struct WorktreeInfo: Identifiable {
        let id: String  // branch name
        let path: String
        let branch: String
    }

    func worktrees(for projectPath: String) -> [WorktreeInfo] {
        let wtDir = (projectPath as NSString).appendingPathComponent(".worktrees")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: wtDir) else { return [] }
        return entries.compactMap { entry in
            let fullPath = (wtDir as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { return nil }
            return WorktreeInfo(id: entry, path: fullPath, branch: entry)
        }
    }

    /// Create a new worktree using the `wt` CLI tool.
    func createWorktree(branch: String, in projectPath: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // Use login shell to pick up wt function from .zshrc
            process.arguments = ["-l", "-c", "cd '\(projectPath.replacingOccurrences(of: "'", with: "'\\''"))' && wt '\(branch.replacingOccurrences(of: "'", with: "'\\''"))' --no-build"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let wtPath = (projectPath as NSString).appendingPathComponent(".worktrees/\(branch)")
                let status = process.terminationStatus
                // Read pipe data off-main before dispatching to main thread
                let errorData = status != 0 ? pipe.fileHandleForReading.readDataToEndOfFile() : nil
                DispatchQueue.main.async {
                    if status == 0 {
                        completion(.success(wtPath))
                    } else {
                        let errorMsg = errorData.flatMap { String(data: $0, encoding: .utf8) } ?? "wt failed with exit code \(status)"
                        completion(.failure(NSError(domain: "wt", code: Int(status), userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Delete a worktree using git.
    func deleteWorktree(branch: String, in projectPath: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["worktree", "remove", ".worktrees/\(branch)"]
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async { completion(process.terminationStatus == 0) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    /// List git branches for a project.
    func branches(for projectPath: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectPath, "branch", "--list", "--format=%(refname:short)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    /// Get current branch for a project path.
    func currentBranch(for projectPath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectPath, "rev-parse", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Recompute groups from current workspace list.
    func update(from workspaces: [any WorkspaceDirectoryProviding]) {
        // Count directory occurrences
        var dirToIds: [String: [UUID]] = [:]
        for ws in workspaces {
            let dir = (ws.workspaceCurrentDirectory as NSString).standardizingPath
            dirToIds[dir, default: []].append(ws.workspaceId)
        }

        // Directories with 2+ workspaces are "projects"; singles are ungrouped
        var newGroups: [ProjectGroup] = []
        var newUngrouped: [UUID] = []

        for (dir, ids) in dirToIds.sorted(by: { $0.key < $1.key }) {
            if ids.count >= 2 {
                let name = (dir as NSString).lastPathComponent
                let wtDir = (dir as NSString).appendingPathComponent(".worktrees")
                let wtCount = (try? FileManager.default.contentsOfDirectory(atPath: wtDir).filter { entry in
                    var isDir: ObjCBool = false
                    let fullPath = (wtDir as NSString).appendingPathComponent(entry)
                    return FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) && isDir.boolValue
                }.count) ?? 0
                newGroups.append(ProjectGroup(
                    id: dir, name: name, directory: dir,
                    workspaceIds: ids, worktreeCount: wtCount
                ))
            } else {
                newUngrouped.append(contentsOf: ids)
            }
        }

        groups = newGroups
        ungroupedIds = newUngrouped
    }
}
