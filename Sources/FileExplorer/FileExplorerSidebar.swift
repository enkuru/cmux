import AppKit
import SwiftUI

struct FileExplorerSidebar: View {
    @EnvironmentObject var tabManager: TabManager
    @Binding var selection: SidebarSelection
    @ObservedObject var treeModel: FileTreeModel
    @AppStorage("fileExplorerRootDirectory") private var rootDirectory = ""
    @AppStorage("fileExplorerShowAllSessions") private var showAllSessions = true
    @AppStorage("fileExplorerVisibleHiddenFolders") private var visibleHiddenFoldersRaw = ""
    @State private var showHiddenFolderSettings = false
    @State private var newHiddenFolderName = ""
    @State private var searchText = ""

    /// Space at top of sidebar for traffic light buttons (matches VerticalTabsSidebar)
    private let trafficLightPadding: CGFloat = 28

    var body: some View {
        let workspaces = ActiveSessionMatcher.workspaceDirectoryInfos(from: tabManager.tabs, selectedTabId: tabManager.selectedTabId)

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer()
                                .frame(height: trafficLightPadding + 26)

                            // Header (below traffic light buttons + view-switcher row)
                            fileExplorerHeader

                            fileSearchField

                            LazyVStack(spacing: 2) {
                            let entries = treeModel.flatVisibleEntries(
                                workspaces: workspaces,
                                showAllSessions: showAllSessions
                            )
                            ForEach(entries) { entry in
                                FileTreeRowView(
                                    entry: entry,
                                    onToggleExpand: {
                                        toggleExpand(path: entry.path)
                                    },
                                    onOpenFolder: {
                                        openFolder(path: entry.path)
                                    },
                                    onFocusSession: {
                                        if case .session(let wsId, _, _, _) = entry.kind {
                                            focusSession(workspaceId: wsId)
                                        }
                                    }
                                )
                                .equatable()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
            }
            }
            // Right-edge boundary is drawn by the shared sidebar resizer overlay.
        }
        .onAppear {
            if rootDirectory.isEmpty {
                rootDirectory = FileManager.default.homeDirectoryForCurrentUser.path
            }
            treeModel.rootPath = (rootDirectory as NSString).expandingTildeInPath
            treeModel.loadRoot()
            treeModel.autoExpandForSessions(workspaces)
            treeModel.refreshGitInfo(for: workspaces)
        }
        .onChange(of: rootDirectory) { newValue in
            treeModel.rootPath = (newValue as NSString).expandingTildeInPath
            treeModel.loadRoot()
            treeModel.autoExpandForSessions(workspaces)
            treeModel.refreshGitInfo(for: workspaces)
        }
        .onChange(of: visibleHiddenFoldersRaw) { _ in
            treeModel.loadRoot()
            let freshWorkspaces = ActiveSessionMatcher.workspaceDirectoryInfos(from: tabManager.tabs)
            treeModel.autoExpandForSessions(freshWorkspaces)
            treeModel.refreshGitInfo(for: freshWorkspaces)
        }
        .onChange(of: tabManager.tabs.count) { _ in
            let freshWorkspaces = ActiveSessionMatcher.workspaceDirectoryInfos(from: tabManager.tabs)
            treeModel.autoExpandForSessions(freshWorkspaces)
            treeModel.refreshGitInfo(for: freshWorkspaces)
        }
        .task(id: searchText) {
            // Debounce rapid typing; `.task(id:)` cancels the prior run on each change.
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
            await treeModel.runSearch(query: searchText)
        }
    }

    // MARK: - Search

    private var fileSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            TextField(
                String(localized: "fileExplorer.search.placeholder", defaultValue: "Search folders"),
                text: $searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .safeHelp(String(localized: "fileExplorer.search.clear.tooltip", defaultValue: "Clear Search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Header

    private var fileExplorerHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(cmuxAccentColor())

            Text(String(localized: "fileExplorer.title", defaultValue: "Files"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            // Change root directory
            Button(action: chooseRootDirectory) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .safeHelp(String(localized: "fileExplorer.changeRoot.tooltip", defaultValue: "Change Root Directory"))

            // Toggle show all sessions
            Button(action: { showAllSessions.toggle() }) {
                Image(systemName: showAllSessions ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(showAllSessions ? cmuxAccentColor() : .secondary)
            }
            .buttonStyle(.plain)
            .safeHelp(String(localized: "fileExplorer.toggleSessions.tooltip", defaultValue: "Toggle Session Visibility"))

            // Visible hidden folders
            Button(action: { showHiddenFolderSettings.toggle() }) {
                Image(systemName: "eye")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(parsedVisibleHiddenFolders.isEmpty ? .secondary : cmuxAccentColor())
            }
            .buttonStyle(.plain)
            .safeHelp(String(localized: "fileExplorer.hiddenFolders.tooltip", defaultValue: "Visible Hidden Folders"))
            .popover(isPresented: $showHiddenFolderSettings) {
                hiddenFolderSettingsPopover
            }

            // Back to tabs
            Button(action: { selection = .tabs }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .safeHelp(String(localized: "fileExplorer.backToTabs.tooltip", defaultValue: "Back to Workspaces"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func toggleExpand(path: String) {
        guard let root = treeModel.rootNode else { return }
        if let node = findNode(path: path, in: root) {
            treeModel.toggleExpansion(node)
        }
    }

    private func openFolder(path: String) {
        tabManager.addWorkspace(workingDirectory: path)
    }

    private func focusSession(workspaceId: UUID) {
        if let workspace = tabManager.tabs.first(where: { $0.id == workspaceId }) {
            tabManager.selectTab(workspace)
        }
        selection = .tabs
    }

    private func chooseRootDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = String(localized: "fileExplorer.openPanel.title", defaultValue: "Choose Root Directory")
        panel.directoryURL = URL(fileURLWithPath: (rootDirectory as NSString).expandingTildeInPath)

        if panel.runModal() == .OK, let url = panel.url {
            rootDirectory = url.path
        }
    }

    // MARK: - Helpers

    private func findNode(path: String, in node: FileTreeNode) -> FileTreeNode? {
        if node.path == path { return node }
        guard let children = node.children else { return nil }
        for child in children {
            if let found = findNode(path: path, in: child) {
                return found
            }
        }
        return nil
    }

    // MARK: - Hidden Folders Settings

    private var parsedVisibleHiddenFolders: [String] {
        visibleHiddenFoldersRaw
            .split(separator: ",")
            .map { String($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private func addHiddenFolder() {
        var name = newHiddenFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !name.hasPrefix(".") { name = ".\(name)" }
        var folders = Set(parsedVisibleHiddenFolders)
        folders.insert(name)
        visibleHiddenFoldersRaw = folders.sorted().joined(separator: ",")
        newHiddenFolderName = ""
    }

    private func removeHiddenFolder(_ name: String) {
        var folders = Set(parsedVisibleHiddenFolders)
        folders.remove(name)
        visibleHiddenFoldersRaw = folders.sorted().joined(separator: ",")
    }

    private var hiddenFolderSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "fileExplorer.hiddenFolders.title", defaultValue: "Visible Hidden Folders"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)

            if parsedVisibleHiddenFolders.isEmpty {
                Text(String(localized: "fileExplorer.hiddenFolders.empty", defaultValue: "No hidden folders added"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ForEach(parsedVisibleHiddenFolders, id: \.self) { name in
                    HStack {
                        Text(name)
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Button(action: { removeHiddenFolder(name) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            HStack(spacing: 4) {
                TextField(
                    String(localized: "fileExplorer.hiddenFolders.placeholder", defaultValue: ".worktree"),
                    text: $newHiddenFolderName
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .onSubmit { addHiddenFolder() }

                Button(action: addHiddenFolder) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(cmuxAccentColor())
                }
                .buttonStyle(.plain)
                .disabled(newHiddenFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}
