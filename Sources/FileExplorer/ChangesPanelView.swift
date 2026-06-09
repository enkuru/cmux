import AppKit
import SwiftUI

/// Dedicated Changes sidebar panel showing git-changed files across all active sessions.
/// Grouped by project directory, with per-file actions (open in editor, revert, stage).
struct ChangesPanelView: View {
    @EnvironmentObject var tabManager: TabManager
    @Binding var selection: SidebarSelection
    @ObservedObject var treeModel: FileTreeModel

    @Environment(\.colorScheme) private var colorScheme

    @State private var collapsedProjects: Set<String> = []
    @State private var collapsedFolders: Set<String> = []

    private let trafficLightPadding: CGFloat = 28

    var body: some View {
        let workspaces = ActiveSessionMatcher.workspaceDirectoryInfos(from: tabManager.tabs)
        let projects = groupedChanges(workspaces: workspaces)

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer()
                                .frame(height: trafficLightPadding + 26)

                            changesHeader(totalCount: projects.reduce(0) { $0 + $1.files.count })

                            if projects.isEmpty {
                                emptyState
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(projects) { project in
                                        projectSection(project)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .frame(minHeight: proxy.size.height, alignment: .top)
                    }
                }
            }
            // Right-edge boundary is drawn by the shared sidebar resizer overlay.
        }
    }

    // MARK: - Header

    private func changesHeader(totalCount: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(cmuxAccentColor())

            Text(String(localized: "changes.title", defaultValue: "Changes"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            if totalCount > 0 {
                Text("\(totalCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(cmuxAccentColor()))
            }

            Spacer(minLength: 0)

            // Refresh button
            Button(action: refreshAll) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .safeHelp(String(localized: "changes.refresh.tooltip", defaultValue: "Refresh Changes"))

            // Back to files
            Button(action: { selection = .files }) {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .safeHelp(String(localized: "changes.backToFiles.tooltip", defaultValue: "Back to Files"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 40)
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
            Text(String(localized: "changes.empty", defaultValue: "No changes detected"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text(String(localized: "changes.empty.detail", defaultValue: "Changes will appear here when agents modify files"))
                .font(.system(size: 10.5, weight: .regular))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Project Section

    private func projectSection(_ project: ProjectChanges) -> some View {
        let isCollapsed = collapsedProjects.contains(project.id)
        let tree = ChangesTreeNode.buildTree(from: project.files)

        return VStack(spacing: 0) {
            // Project header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed {
                        collapsedProjects.remove(project.id)
                    } else {
                        collapsedProjects.insert(project.id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                    Image(systemName: "folder.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(cmuxAccentColor())

                    Text(project.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let branch = project.branch {
                        Text(branch)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Text("\(project.files.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // File/folder tree
            if !isCollapsed {
                ForEach(tree) { node in
                    treeNodeView(node: node, projectId: project.id, projectPath: project.directory, depth: 0)
                }
            }
        }
    }

    // MARK: - Tree Node View

    @ViewBuilder
    private func treeNodeView(node: ChangesTreeNode, projectId: String, projectPath: String, depth: Int) -> some View {
        let indent = CGFloat(depth) * 12

        if let file = node.file {
            changedFileRow(file: file, projectPath: projectPath)
                .padding(.leading, indent)
        } else {
            let folderKey = "\(projectId)/\(node.path)"
            let isCollapsed = collapsedFolders.contains(folderKey)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed {
                        collapsedFolders.remove(folderKey)
                    } else {
                        collapsedFolders.insert(folderKey)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                    Image(systemName: "folder")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))

                    Text(node.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.leading, 16 + indent)
                .padding(.trailing, 12)
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                ForEach(node.children) { child in
                    AnyView(treeNodeView(node: child, projectId: projectId, projectPath: projectPath, depth: depth + 1))
                }
            }
        }
    }

    // MARK: - Changed File Row

    private func changedFileRow(file: GitChangedFile, projectPath: String) -> some View {
        ChangedFileRowView(file: file, projectPath: projectPath, onOpenDiff: {
            openDiffInBrowser(file: file, projectPath: projectPath)
        })
    }

    private func openDiffInBrowser(file: GitChangedFile, projectPath: String) {
        let html = GitInfo.diffHTML(for: file.name, status: file.status, in: projectPath)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-diffs", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let safeName = file.name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let htmlFile = tempDir.appendingPathComponent("\(safeName).html")
        try? html.write(to: htmlFile, atomically: true, encoding: .utf8)

        tabManager.openBrowser(url: htmlFile)
    }

    // MARK: - Data

    private func groupedChanges(workspaces: [WorkspaceDirectoryInfo]) -> [ProjectChanges] {
        var seen = Set<String>()
        var projects: [ProjectChanges] = []

        for ws in workspaces {
            let normalized = (ws.directory as NSString).standardizingPath
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)

            guard let gitInfo = treeModel.gitInfoCache[normalized],
                  !gitInfo.changedFiles.isEmpty else { continue }

            let name = (ws.directory as NSString).lastPathComponent
            projects.append(ProjectChanges(
                id: normalized,
                name: name,
                directory: ws.directory,
                branch: gitInfo.branch,
                files: gitInfo.changedFiles
            ))
        }

        return projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func refreshAll() {
        let workspaces = ActiveSessionMatcher.workspaceDirectoryInfos(from: tabManager.tabs)
        treeModel.refreshGitInfo(for: workspaces)
    }
}

// MARK: - Tree Node

/// A node in the changes folder tree. Leaf nodes hold a file; interior nodes hold children.
/// Single-child directory chains are compacted (e.g. `src/main/service` as one row).
private struct ChangesTreeNode: Identifiable {
    let id: String
    let name: String       // display name (compacted path segment)
    let path: String       // full relative path from project root
    let file: GitChangedFile?
    var children: [ChangesTreeNode]

    static func buildTree(from files: [GitChangedFile]) -> [ChangesTreeNode] {
        var root: [String: Any] = [:]
        for file in files {
            let components = file.name.split(separator: "/").map(String.init)
            insertIntoDict(&root, components: components, file: file)
        }
        return nodesFromDict(root, parentPath: "")
    }

    private static func insertIntoDict(_ dict: inout [String: Any], components: [String], file: GitChangedFile) {
        guard !components.isEmpty else { return }
        if components.count == 1 {
            dict[components[0]] = file
        } else {
            var sub = (dict[components[0]] as? [String: Any]) ?? [:]
            insertIntoDict(&sub, components: Array(components.dropFirst()), file: file)
            dict[components[0]] = sub
        }
    }

    private static func nodesFromDict(_ dict: [String: Any], parentPath: String) -> [ChangesTreeNode] {
        var folders: [ChangesTreeNode] = []
        var leaves: [ChangesTreeNode] = []

        for (key, value) in dict.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
            let path = parentPath.isEmpty ? key : "\(parentPath)/\(key)"

            if let file = value as? GitChangedFile {
                leaves.append(ChangesTreeNode(
                    id: path,
                    name: (file.name as NSString).lastPathComponent,
                    path: path,
                    file: file,
                    children: []
                ))
            } else if let subDict = value as? [String: Any] {
                var children = nodesFromDict(subDict, parentPath: path)

                // Compact single-child directories
                var displayName = key
                var compactedPath = path
                var current = children
                while current.count == 1, current[0].file == nil {
                    displayName = "\(displayName)/\(current[0].name)"
                    compactedPath = current[0].path
                    current = current[0].children
                }

                folders.append(ChangesTreeNode(
                    id: compactedPath,
                    name: displayName,
                    path: compactedPath,
                    file: nil,
                    children: current
                ))
            }
        }

        return folders + leaves
    }
}

// MARK: - Data Model

private struct ProjectChanges: Identifiable {
    let id: String
    let name: String
    let directory: String
    let branch: String?
    let files: [GitChangedFile]
}

// MARK: - Changed File Row

private struct ChangedFileRowView: View {
    let file: GitChangedFile
    let projectPath: String
    let onOpenDiff: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            // Status indicator
            Text(file.status.symbol)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(statusColor)
                .frame(width: 14, alignment: .center)

            // File name
            Text(fileName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
                .safeHelp(file.name)

            Spacer(minLength: 0)

            // Quick actions on hover
            if isHovering {
                // Open in editor
                Button {
                    let fullPath = (projectPath as NSString).appendingPathComponent(file.name)
                    if let editor = ExternalEditor.available.first(where: { $0 != .finder && $0 != .terminal }) {
                        editor.open(path: fullPath)
                    }
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                // Revert file
                Button {
                    revertFile()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color(nsColor: sidebarSelectedWorkspaceBackgroundNSColor(for: colorScheme)).opacity(0.3) : Color.clear)
        )
        .padding(.horizontal, 6)
        .onTapGesture {
            onOpenDiff()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            contextMenuContent
        }
    }

    private var fileName: String {
        (file.name as NSString).lastPathComponent
    }

    private var statusColor: Color {
        switch file.status {
        case .modified: return .orange
        case .added, .untracked: return .green
        case .deleted: return .red
        case .renamed: return .blue
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        let fullPath = (projectPath as NSString).appendingPathComponent(file.name)

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(fullPath, forType: .string)
        } label: {
            Label(String(localized: "context.copyPath", defaultValue: "Copy Path"), systemImage: "doc.on.doc")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.name, forType: .string)
        } label: {
            Label(String(localized: "context.copyRelativePath", defaultValue: "Copy Relative Path"), systemImage: "doc.on.clipboard")
        }

        Divider()

        let editors = ExternalEditor.available.filter { $0 != .terminal && $0 != .finder }
        ForEach(editors, id: \.self) { editor in
            Button {
                editor.open(path: fullPath)
            } label: {
                Label(editor.displayName, systemImage: editor.iconName)
            }
        }

        Divider()

        Button {
            revertFile()
        } label: {
            Label(String(localized: "changes.revert", defaultValue: "Revert File"), systemImage: "arrow.uturn.backward")
        }

        Button {
            stageFile()
        } label: {
            Label(String(localized: "changes.stage", defaultValue: "Stage File"), systemImage: "plus.circle")
        }
    }

    private func revertFile() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = file.status == .untracked
            ? ["clean", "-f", "--", file.name]
            : ["checkout", "--", file.name]
        task.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        try? task.run()
    }

    private func stageFile() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["add", "--", file.name]
        task.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        try? task.run()
    }
}
