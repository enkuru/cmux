import SwiftUI

struct WorktreeEntry: Identifiable, Equatable {
    let id: String
    let path: String
    let branch: String
    let isWorktree: Bool
}

struct WorktreeDropdown: View {
    let projectPath: String
    let currentBranch: String?
    let onSelectWorktree: (String) -> Void
    let onCreateWorktree: () -> Void
    let onDeleteWorktree: (String) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var entries: [WorktreeEntry] = []
    @State private var isLoading = true

    private var filteredEntries: [WorktreeEntry] {
        if searchText.isEmpty { return entries }
        return entries.filter { $0.branch.localizedCaseInsensitiveContains(searchText) }
    }

    private var worktreeEntries: [WorktreeEntry] {
        filteredEntries.filter { $0.isWorktree }
    }

    private var branchEntries: [WorktreeEntry] {
        filteredEntries.filter { !$0.isWorktree }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField(String(localized: "worktree.search.placeholder", defaultValue: "Search..."), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)

            Divider()

            // Current branch header
            if let branch = currentBranch {
                HStack {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    Text(branch)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(String(localized: "worktree.current", defaultValue: "Current"))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
            }

            Divider()

            // Entry list
            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "worktree.loading", defaultValue: "Loading..."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            } else if filteredEntries.isEmpty {
                Text(searchText.isEmpty
                    ? String(localized: "worktree.empty", defaultValue: "No worktrees or branches")
                    : String(localized: "worktree.noResults", defaultValue: "No results"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Worktrees section
                        if !worktreeEntries.isEmpty {
                            Text(String(localized: "worktree.section.worktrees", defaultValue: "WORKTREES"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            ForEach(worktreeEntries) { entry in
                                WorktreeEntryRow(
                                    entry: entry,
                                    isSelected: entry.branch == currentBranch,
                                    onSelect: {
                                        onSelectWorktree(entry.path)
                                        onDismiss()
                                    },
                                    onDelete: { onDeleteWorktree(entry.branch) }
                                )
                            }
                        }

                        // Branches section
                        if !branchEntries.isEmpty {
                            Text(String(localized: "worktree.section.branches", defaultValue: "BRANCHES"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            ForEach(branchEntries) { entry in
                                WorktreeEntryRow(
                                    entry: entry,
                                    isSelected: entry.branch == currentBranch,
                                    onSelect: {
                                        onSelectWorktree(entry.path)
                                        onDismiss()
                                    },
                                    onDelete: nil
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }

            Divider()

            // New worktree action
            Button {
                onCreateWorktree()
                onDismiss()
            } label: {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text(String(localized: "worktree.new", defaultValue: "New Worktree..."))
                        .font(.system(size: 11))
                }
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .frame(width: 280)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .onAppear {
            loadEntries()
        }
    }

    private func loadEntries() {
        DispatchQueue.global(qos: .userInitiated).async {
            var allEntries: [WorktreeEntry] = []
            var seenBranches: Set<String> = []

            // Load worktrees
            let wtDir = (projectPath as NSString).appendingPathComponent(".worktrees")
            if let wtEntries = try? FileManager.default.contentsOfDirectory(atPath: wtDir) {
                for entry in wtEntries {
                    let fullPath = (wtDir as NSString).appendingPathComponent(entry)
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                        allEntries.append(WorktreeEntry(id: "wt-\(entry)", path: fullPath, branch: entry, isWorktree: true))
                        seenBranches.insert(entry)
                    }
                }
            }

            // Load branches
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
                if let output = String(data: data, encoding: .utf8) {
                    let branchList = output.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty && !seenBranches.contains($0) }
                    for branch in branchList {
                        allEntries.append(WorktreeEntry(id: "br-\(branch)", path: branch, branch: branch, isWorktree: false))
                    }
                }
            } catch {
                // Ignore errors
            }

            DispatchQueue.main.async {
                entries = allEntries
                isLoading = false
            }
        }
    }
}

private struct WorktreeEntryRow: View {
    let entry: WorktreeEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.isWorktree ? "arrow.triangle.branch" : "arrow.branch")
                .font(.system(size: 10))
                .foregroundColor(entry.isWorktree ? .orange : .secondary)

            Text(entry.branch)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            if isHovering, let onDelete = onDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onSelect() }
    }
}
