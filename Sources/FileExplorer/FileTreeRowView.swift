import AppKit
import SwiftUI

// MARK: - External Editor Support

enum ExternalEditor: CaseIterable {
    case vscode
    case cursor
    case intellij
    case webstorm
    case sublime
    case xcode
    case finder
    case terminal

    var displayName: String {
        switch self {
        case .vscode: return "VS Code"
        case .cursor: return "Cursor"
        case .intellij: return "IntelliJ IDEA"
        case .webstorm: return "WebStorm"
        case .sublime: return "Sublime Text"
        case .xcode: return "Xcode"
        case .finder: return String(localized: "editor.finder", defaultValue: "Finder")
        case .terminal: return String(localized: "editor.newTerminal", defaultValue: "New Terminal Here")
        }
    }

    var iconName: String {
        switch self {
        case .vscode: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .intellij: return "hammer"
        case .webstorm: return "globe"
        case .sublime: return "text.cursor"
        case .xcode: return "wrench.and.screwdriver"
        case .finder: return "folder"
        case .terminal: return "terminal"
        }
    }

    /// Bundle identifier used for app detection and launching via `open -b`
    private var bundleIdentifier: String? {
        switch self {
        case .vscode: return "com.microsoft.VSCode"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .intellij: return "com.jetbrains.intellij"
        case .webstorm: return "com.jetbrains.WebStorm"
        case .sublime: return "com.sublimetext.4"
        case .xcode: return "com.apple.dt.Xcode"
        case .finder, .terminal: return nil
        }
    }

    /// Fallback bundle IDs (e.g. community edition vs ultimate)
    private var alternateBundleIdentifiers: [String] {
        switch self {
        case .intellij: return ["com.jetbrains.intellij.ce"]
        case .sublime: return ["com.sublimetext.3"]
        case .vscode: return ["com.microsoft.VSCodeInsiders"]
        case .cursor: return ["com.cursor.Cursor"]
        default: return []
        }
    }

    var isAvailable: Bool {
        switch self {
        case .finder, .terminal: return true
        default:
            return resolvedBundleId != nil
        }
    }

    /// Finds the first installed bundle ID (primary or alternates)
    private var resolvedBundleId: String? {
        var candidates = [String]()
        if let primary = bundleIdentifier { candidates.append(primary) }
        candidates.append(contentsOf: alternateBundleIdentifiers)
        for bid in candidates {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil {
                return bid
            }
        }
        return nil
    }

    func open(path: String) {
        switch self {
        case .finder:
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        case .terminal:
            break
        default:
            guard let bid = resolvedBundleId else { return }
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.open(
                [url],
                withAppBundleIdentifier: bid,
                options: [],
                additionalEventParamDescriptor: nil,
                launchIdentifiers: nil
            )
        }
    }

    static var available: [ExternalEditor] {
        allCases.filter { $0.isAvailable }
    }
}

// MARK: - File Tree Row View (dispatches to folder or session row)

struct FileTreeRowView: View, Equatable {
    let entry: FileTreeEntry
    let onToggleExpand: () -> Void
    let onOpenFolder: () -> Void
    let onFocusSession: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    static func == (lhs: FileTreeRowView, rhs: FileTreeRowView) -> Bool {
        lhs.entry == rhs.entry
    }

    var body: some View {
        switch entry.kind {
        case .folder(let isExpanded, let hasChildren, let sessionCount, let gitBranch):
            folderRow(isExpanded: isExpanded, hasChildren: hasChildren, sessionCount: sessionCount, gitBranch: gitBranch)
        case .session(_, let title, let status, let summary):
            sessionRow(title: title, status: status, summary: summary)
        case .changedFile:
            EmptyView()
        }
    }

    // MARK: - Folder Row

    private func folderRow(isExpanded: Bool, hasChildren: Bool, sessionCount: Int, gitBranch: String? = nil) -> some View {
        HStack(spacing: 6) {
            // Disclosure chevron
            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .opacity(hasChildren ? 1 : 0.3)

            // Folder icon
            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(sessionCount > 0 ? cmuxAccentColor() : .secondary.opacity(0.7))

            // Folder name
            Text(entry.name)
                .font(.system(size: 12.5, weight: sessionCount > 0 ? .semibold : .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            // Git branch badge
            if let gitBranch {
                Text(gitBranch)
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

            // Session count badge
            if sessionCount > 0 {
                Text("\(sessionCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(
                        Capsule()
                            .fill(cmuxAccentColor())
                    )
            }
        }
        .padding(.leading, CGFloat(entry.depth) * 16 + 10)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color(nsColor: sidebarSelectedWorkspaceBackgroundNSColor(for: colorScheme)).opacity(0.5) : Color.clear)
        )
        .padding(.horizontal, 6)
        .onTapGesture(count: 2) {
            onOpenFolder()
        }
        .onTapGesture(count: 1) {
            onToggleExpand()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            folderContextMenu(path: entry.path)
        }
    }

    // MARK: - Session Row

    private func sessionRow(title: String, status: AgentStatus, summary: String? = nil) -> some View {
        HStack(spacing: 6) {
            // Spacer for chevron alignment
            Color.clear
                .frame(width: 12, height: 12)

            // Status icon (replaces generic terminal icon)
            Image(systemName: status.iconName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(agentStatusColor(status))

            // Session title + summary
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: status == .needsAttention ? .semibold : .regular))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let summary {
                    Text(summary)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            // Status label on hover
            if isHovering {
                Text(status.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(agentStatusColor(status))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(agentStatusColor(status).opacity(0.12))
                    )
            }
        }
        .padding(.leading, CGFloat(entry.depth) * 16 + 10)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color(nsColor: sidebarSelectedWorkspaceBackgroundNSColor(for: colorScheme)).opacity(0.5) : Color.clear)
        )
        .padding(.horizontal, 6)
        .onTapGesture {
            onFocusSession()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            folderContextMenu(path: entry.path)
        }
    }

    private func agentStatusColor(_ status: AgentStatus) -> Color {
        switch status {
        case .idle: return .secondary
        case .running: return cmuxAccentColor()
        case .needsAttention: return .orange
        case .completed: return .green
        case .errored: return .red
        }
    }

    private func changedFileColor(for status: GitFileStatus) -> Color {
        switch status {
        case .modified: return .orange
        case .added, .untracked: return .green
        case .deleted: return .red
        case .renamed: return .blue
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func folderContextMenu(path: String) -> some View {
        let editors = ExternalEditor.available.filter { $0 != .terminal }

        Section(String(localized: "context.openWith", defaultValue: "Open With")) {
            ForEach(editors, id: \.self) { editor in
                Button {
                    editor.open(path: path)
                } label: {
                    Label(editor.displayName, systemImage: editor.iconName)
                }
            }
        }

        Divider()

        Button {
            onOpenFolder()
        } label: {
            Label(
                String(localized: "context.newTerminalHere", defaultValue: "New Terminal Here"),
                systemImage: "terminal"
            )
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        } label: {
            Label(
                String(localized: "context.copyPath", defaultValue: "Copy Path"),
                systemImage: "doc.on.doc"
            )
        }
    }
}
