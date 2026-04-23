import SwiftUI

/// A clickable branch badge that opens branch/worktree management.
struct WorktreeBadge: View {
    let currentDirectory: String
    let currentBranch: String?
    let onSwitchBranch: (String) -> Void      // git checkout
    let onSwitchWorktree: (String) -> Void    // cd to worktree path
    let onCreateWorktree: (String) -> Void    // create worktree from branch

    @State private var showSheet = false

    private var isWorktree: Bool {
        currentDirectory.contains("/.worktrees/")
    }

    var body: some View {
        if currentBranch != nil {
            Button {
                showSheet = true
            } label: {
                badgeLabel
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSheet) {
                BranchWorktreeSheet(
                    currentDirectory: currentDirectory,
                    currentBranch: currentBranch,
                    isWorktree: isWorktree,
                    onSwitchBranch: { branch in
                        onSwitchBranch(branch)
                        showSheet = false
                    },
                    onSwitchWorktree: { path in
                        onSwitchWorktree(path)
                        showSheet = false
                    },
                    onCreateWorktree: { branch in
                        onCreateWorktree(branch)
                        showSheet = false
                    },
                    onDismiss: { showSheet = false }
                )
            }
        }
    }

    private var badgeLabel: some View {
        HStack(spacing: 2) {
            Image(systemName: isWorktree ? "arrow.triangle.branch" : "arrow.branch")
                .font(.system(size: 10))
                .foregroundColor(isWorktree ? .orange : .secondary)
            Image(systemName: "chevron.down")
                .font(.system(size: 7))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(isWorktree ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.1))
        .cornerRadius(4)
        .help(currentBranch ?? "")
    }
}

// MARK: - Sheet with Tabs

struct BranchWorktreeSheet: View {
    let currentDirectory: String
    let currentBranch: String?
    let isWorktree: Bool
    let onSwitchBranch: (String) -> Void
    let onSwitchWorktree: (String) -> Void
    let onCreateWorktree: (String) -> Void
    let onDismiss: () -> Void

    @State private var selectedTab = 0  // 0 = branches, 1 = worktrees
    @State private var searchText = ""
    @State private var branches: [String] = []
    @State private var worktrees: [ProjectGrouping.WorktreeInfo] = []
    @State private var mainRepoBranch: String?

    private var projectPath: String {
        if let range = currentDirectory.range(of: "/.worktrees/") {
            return String(currentDirectory[currentDirectory.startIndex..<range.lowerBound])
        }
        return currentDirectory
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(String(localized: "git.title", defaultValue: "Git"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text(String(localized: "git.tab.branches", defaultValue: "Branches")).tag(0)
                Text(String(localized: "git.tab.worktrees", defaultValue: "Worktrees")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(String(localized: "git.search", defaultValue: "Search..."), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Content
            if selectedTab == 0 {
                BranchesTab(
                    branches: branches,
                    currentBranch: currentBranch,
                    searchText: searchText,
                    onSwitchBranch: onSwitchBranch
                )
            } else {
                WorktreesTab(
                    worktrees: worktrees,
                    branches: branches,
                    currentBranch: currentBranch,
                    currentDirectory: currentDirectory,
                    searchText: searchText,
                    projectPath: projectPath,
                    mainRepoBranch: mainRepoBranch,
                    onSwitchWorktree: onSwitchWorktree,
                    onCreateWorktree: onCreateWorktree
                )
            }
        }
        .frame(width: 360, height: 450)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loadData() }
    }

    private func loadData() {
        let grouping = ProjectGrouping()
        worktrees = grouping.worktrees(for: projectPath)
        branches = grouping.branches(for: projectPath)
        mainRepoBranch = grouping.currentBranch(for: projectPath)
    }
}

// MARK: - Branches Tab

private struct BranchesTab: View {
    let branches: [String]
    let currentBranch: String?
    let searchText: String
    let onSwitchBranch: (String) -> Void

    private var filteredBranches: [String] {
        if searchText.isEmpty { return branches }
        return branches.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Current branch
            if let branch = currentBranch {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(branch)
                        .font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Text(String(localized: "git.current", defaultValue: "Current"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.1))
            }

            Divider()

            // Branch list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filteredBranches.isEmpty {
                        emptyState(String(localized: "git.noBranches", defaultValue: "No branches found"))
                    } else {
                        ForEach(filteredBranches, id: \.self) { branch in
                            BranchRow(
                                branch: branch,
                                isCurrent: branch == currentBranch,
                                onSelect: { onSwitchBranch(branch) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(20)
    }
}

private struct BranchRow: View {
    let branch: String
    let isCurrent: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.branch")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text(branch)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                Spacer()
                if isHovering && !isCurrent {
                    Text(String(localized: "git.checkout", defaultValue: "checkout"))
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .opacity(isCurrent ? 0.5 : 1)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Worktrees Tab

private struct WorktreesTab: View {
    let worktrees: [ProjectGrouping.WorktreeInfo]
    let branches: [String]
    let currentBranch: String?
    let currentDirectory: String
    let searchText: String
    let projectPath: String
    let mainRepoBranch: String?  // Pass this in from parent
    let onSwitchWorktree: (String) -> Void
    let onCreateWorktree: (String) -> Void

    @State private var newBranchName = ""
    @State private var showNewBranchField = false

    // Include main repo as a worktree
    private var allWorktrees: [ProjectGrouping.WorktreeInfo] {
        var all: [ProjectGrouping.WorktreeInfo] = []
        // Add main repo worktree if we have branch info
        if let mainBranch = mainRepoBranch {
            let mainWorktree = ProjectGrouping.WorktreeInfo(
                id: "main-\(mainBranch)",
                path: projectPath,
                branch: mainBranch
            )
            all.append(mainWorktree)
        }
        all.append(contentsOf: worktrees)
        return all
    }

    private var filteredWorktrees: [ProjectGrouping.WorktreeInfo] {
        if searchText.isEmpty { return allWorktrees }
        return allWorktrees.filter { $0.branch.localizedCaseInsensitiveContains(searchText) }
    }

    private var existingWorktreeBranches: Set<String> {
        Set(allWorktrees.map { $0.branch })
    }

    private var availableBranchesForWorktree: [String] {
        branches.filter { !existingWorktreeBranches.contains($0) }
    }

    private var filteredAvailableBranches: [String] {
        if searchText.isEmpty { return availableBranchesForWorktree }
        return availableBranchesForWorktree.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var isInWorktree: Bool {
        currentDirectory.contains("/.worktrees/")
    }

    private func isCurrentWorktree(_ wt: ProjectGrouping.WorktreeInfo) -> Bool {
        // Normalize paths for comparison
        let currentNormalized = (currentDirectory as NSString).standardizingPath
        let wtNormalized = (wt.path as NSString).standardizingPath
        return currentNormalized == wtNormalized || currentNormalized.hasPrefix(wtNormalized + "/")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Existing worktrees (including main)
                sectionHeader(String(localized: "git.worktrees", defaultValue: "WORKTREES"))

                if filteredWorktrees.isEmpty {
                    emptyMessage(String(localized: "git.noMatchingWorktrees", defaultValue: "No matching worktrees"))
                } else {
                    ForEach(filteredWorktrees) { wt in
                        WorktreeRow(
                            worktree: wt,
                            isMain: wt.path == projectPath,
                            isCurrent: isCurrentWorktree(wt),
                            onSelect: { onSwitchWorktree(wt.path) }
                        )
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // Create from existing branch
                sectionHeader(String(localized: "git.createFromBranch", defaultValue: "CREATE FROM EXISTING BRANCH"))

                if filteredAvailableBranches.isEmpty && availableBranchesForWorktree.isEmpty {
                    emptyMessage(String(localized: "git.allBranchesHaveWorktrees", defaultValue: "All branches already have worktrees"))
                } else if filteredAvailableBranches.isEmpty {
                    emptyMessage(String(localized: "git.noMatchingBranches", defaultValue: "No matching branches"))
                } else {
                    ForEach(filteredAvailableBranches.prefix(10), id: \.self) { branch in
                        CreateWorktreeRow(
                            branch: branch,
                            onCreate: { onCreateWorktree(branch) }
                        )
                    }
                    if filteredAvailableBranches.count > 10 {
                        Text("+\(filteredAvailableBranches.count - 10) more")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // Create new branch + worktree
                sectionHeader(String(localized: "git.createNewBranch", defaultValue: "CREATE NEW BRANCH + WORKTREE"))

                if showNewBranchField {
                    HStack {
                        TextField(String(localized: "git.branchName", defaultValue: "Branch name..."), text: $newBranchName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)

                        Button {
                            if !newBranchName.isEmpty {
                                onCreateWorktree(newBranchName)
                                newBranchName = ""
                                showNewBranchField = false
                            }
                        } label: {
                            Text(String(localized: "git.create", defaultValue: "Create"))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newBranchName.isEmpty)

                        Button {
                            showNewBranchField = false
                            newBranchName = ""
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                } else {
                    Button {
                        showNewBranchField = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                            Text(String(localized: "git.newBranchWorktree", defaultValue: "New branch + worktree..."))
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }
}

private struct WorktreeRow: View {
    let worktree: ProjectGrouping.WorktreeInfo
    let isMain: Bool
    let isCurrent: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isMain ? "folder.fill" : "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundColor(isMain ? .blue : .orange)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(worktree.branch)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                    if isMain {
                        Text(String(localized: "git.mainRepo", defaultValue: "main repository"))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if isCurrent {
                    Text(String(localized: "git.current", defaultValue: "Current"))
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(4)
                } else if isHovering {
                    Text(String(localized: "git.switch", defaultValue: "switch"))
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isCurrent ? Color.green.opacity(0.05) : (isHovering ? Color.secondary.opacity(0.1) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .onHover { isHovering = $0 }
    }
}

private struct CreateWorktreeRow: View {
    let branch: String
    let onCreate: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onCreate) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                Text(branch)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                Spacer()
                if isHovering {
                    Text(String(localized: "git.create", defaultValue: "create"))
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
